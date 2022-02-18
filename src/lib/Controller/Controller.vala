using LibPeer.Util;
using LibPeer.Protocols;
using LibPeer;

namespace Downlink {

    public class DownlinkController : PeerApplication {

        private Store store;
        private DownlinkInstance server;
        private Thread<void> server_thread;
        private ConcurrentHashMap<PublisherKey, PeerGroup> peer_groups = new ConcurrentHashMap<PublisherKey, PeerGroup>((a) => a.hash(), (a, b) => a.compare(b) == 0);
        private ConcurrentHashMap<Mx2.InstanceReference, DownlinkPeer> peers = new ConcurrentHashMap<Mx2.InstanceReference, DownlinkPeer>((a) => a.hash(), (a, b) => a.compare(b) == 0);
        public bool is_mirror { get; private set; }

        public DownlinkController(Store store, PublisherKey[] subscriptions, bool mirror_mode = false) {
            this.store = store;
            is_mirror = mirror_mode;
            initialise("Downlink");
            foreach (var subscription in subscriptions) {
                peer_groups.set(subscription, new PeerGroup(subscription));
                if(is_mirror) {
                    information.resource_set.add(get_mirror_resource_identifier(subscription));
                }
                else {
                    information.resource_set.add(get_comrade_resource_identifier(subscription));
                }
            }
            server = new DownlinkInstance(transport, store);
            server_thread = new Thread<void>("Downlink server", run_forever);
        }

        private void run_forever() {
            while(true) {
                server.service_peers();
            }
        }

        public void join_server_thread() {
            server_thread.join();
        }

        protected override void on_new_discovery_peer () {
            foreach (var group in peer_groups) {
                var peer_group = group.value;
                find_resource_peer (get_mirror_resource_identifier(group.key)).on_answer.connect(a => contact_mirror(peer_group, a));
                if(!is_mirror) {
                    find_resource_peer (get_comrade_resource_identifier(group.key)).on_answer.connect(a => contact_comrade(peer_group, a));
                }
            }
        }

        private void contact_mirror(PeerGroup group, Aip.InstanceInformation peer_info) {
            if(peers.has_key(peer_info.instance_reference)) {
                group.add_mirror(peers.get(peer_info.instance_reference));
                return;
            }

            var peer = new DownlinkPeer(peer_info.instance_reference);
            peer.peer_ready.connect(group.add_mirror);
            peers.set(peer_info.instance_reference, peer);
            inquire(peer_info);
        }

        private void contact_comrade(PeerGroup group, Aip.InstanceInformation peer_info) {
            if(peers.has_key(peer_info.instance_reference)) {
                group.add_mirror(peers.get(peer_info.instance_reference));
                return;
            }

            var peer = new DownlinkPeer(peer_info.instance_reference);
            peer.peer_ready.connect(group.add_comrade);
            peers.set(peer_info.instance_reference, peer);
            inquire(peer_info);
        }

        protected override void on_incoming_stream (Stp.Streams.StpInputStream stream) {
            server.handle_stream(stream);
        }
		protected override void on_peer_available (Mx2.InstanceReference peer) {
            if(peers.has_key (peer)) {
                try {
                    peers.get(peer).establish_communication(transport);
                }
                catch {
                    warning("Failed to establish communication with peer");
                }
            }
            else {
                info("Peer replied to inquiry that we didn't send");
            }
        }

        private static Bytes get_comrade_resource_identifier(PublisherKey key) {
            var sum = new Checksum (ChecksumType.SHA256);
            sum.update (key.key_bytes, key.key_bytes.length);
            var identifier = new uint8[SHA256_SIZE];
            size_t size = SHA256_SIZE;
            sum.get_digest (identifier, ref size);
            return new Bytes(identifier);
        }

        private static Bytes get_mirror_resource_identifier(PublisherKey key) {
            return new Bytes(key.key_bytes);
        }

        private bool has_key(PublisherKey key) {
            return peer_groups.has_key(key);
        }

        private delegate T PeerCallback<T>(DownlinkPeer peer) throws IOError, Error;

        private T try_peers<T>(PublisherKey key, PeerCallback<T> callback) throws IOError, Error {
            var group = peer_groups.get(key);
            Error err = new IOError.NETWORK_UNREACHABLE("No peers found to service the request.");
            for(var i = 0; i < 5 && i < group.comrade_count(); i++) {
                try {
                    return callback(group.get_comrade());
                }
                catch (Error e) { err = e; }
            }
            group.wait_for_mirror();
            for(var i = 0; i < group.mirror_count(); i++) {
                try {
                    return callback(group.get_mirror());
                }
                catch (Error e) { err = e; }
            }
            throw err;
        }

        public Metadata get_metadata(PublisherKey key) throws Error, IOError requires (has_key(key))  {
            return store.read_metadata(key, () => try_peers<Metadata>(key, p => p.get_metadata(key)));
        }

        public uint8[] get_resource(PublisherKey key, ResourceIdentifier resource, uint64 start = 0, uint64? end = null) throws Error, IOError requires (has_key(key)) {
            var chunk_start = start - (start % AUTHTABLE_CHUNK_SIZE);
            var chunk_end = end ?? resource.size;
            if(end != null && end % AUTHTABLE_CHUNK_SIZE != 0) {
                chunk_end = uint64.min(resource.size, end + (AUTHTABLE_CHUNK_SIZE - (end % AUTHTABLE_CHUNK_SIZE)));
            }

            var auth_table = store.read_auth_table(resource, () => {
                return try_peers<AuthTable>(key, p => {
                    return p.get_auth_table(resource);
                });
            });

            return store.read_resource(resource, chunk_start, chunk_end, (s, e) => {
                return try_peers<Bytes>(key, p => {
                    var resource_data = p.get_resource_part(resource, s, e);
                    for(var i = chunk_start; i < chunk_end; i += AUTHTABLE_CHUNK_SIZE) {
                        if(!auth_table.verify_chunk(resource_data[i:i+AUTHTABLE_CHUNK_SIZE], (int)(i / AUTHTABLE_CHUNK_SIZE))) {
                            throw new IOError.INVALID_DATA("Verification of resource data against the auth table failed.");
                        }
                    }
                    return new Bytes(resource_data);
                }).get_data();
            });
        }
    }

}