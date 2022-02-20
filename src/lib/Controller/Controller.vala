using LibPeer.Util;
using LibPeer.Protocols;
using LibPeer;

using Downlink.Util;

namespace Downlink {

    public class DownlinkController : PeerApplication {

        private Store store;
        private Instance server;
        private Thread<void> server_thread;
        private ConcurrentHashMap<PublisherKey, PeerGroup> peer_groups = new ConcurrentHashMap<PublisherKey, PeerGroup>((a) => a.hash(), (a, b) => a.compare(b) == 0);
        private ConcurrentHashMap<Mx2.InstanceReference, Peer> peers = new ConcurrentHashMap<Mx2.InstanceReference, Peer>((a) => a.hash(), (a, b) => a.compare(b) == 0);
        public bool is_mirror { get; private set; }

        public DownlinkController(Store store, PublisherKey[] subscriptions, bool mirror_mode = false) {
            this.store = store;
            is_mirror = mirror_mode;
            initialise("Downlink");
            foreach (var subscription in subscriptions) {
                peer_groups.set(subscription, new PeerGroup());
                if(is_mirror) {
                    information.resource_set.add(get_mirror_resource_identifier(subscription));
                }
                else {
                    information.resource_set.add(get_comrade_resource_identifier(subscription));
                }
            }
            server = new Instance(transport, store);
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

            var peer = new Peer(peer_info.instance_reference);
            peer.peer_ready.connect(group.add_mirror);
            peers.set(peer_info.instance_reference, peer);
            inquire(peer_info);
        }

        private void contact_comrade(PeerGroup group, Aip.InstanceInformation peer_info) {
            if(peers.has_key(peer_info.instance_reference)) {
                group.add_mirror(peers.get(peer_info.instance_reference));
                return;
            }

            var peer = new Peer(peer_info.instance_reference);
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
            sum.update (key.public_key, key.public_key.length);
            var identifier = new uint8[SHA256_SIZE];
            size_t size = SHA256_SIZE;
            sum.get_digest (identifier, ref size);
            return new Bytes(identifier);
        }

        private static Bytes get_mirror_resource_identifier(PublisherKey key) {
            return new Bytes(key.public_key);
        }

        private bool has_key(PublisherKey key) {
            return peer_groups.has_key(key);
        }

        private delegate T PeerCallback<T>(Peer peer) throws IOError, Error;

        private T try_peers<T>(PublisherKey key, PeerCallback<T> callback) throws IOError, Error {
            print("Trying peers\n");
            var group = peer_groups.get(key);
            Error err = new IOError.NETWORK_UNREACHABLE("No peers found to service the request.");
            for(var i = 0; i < 5 && i < group.comrade_count(); i++) {
                try {
                    return callback(group.get_comrade());
                }
                catch (Error e) { err = e; }
            }
            print("Waiting for a mirror\n");
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
                    for(uint64 i = 0; i < (chunk_end - chunk_start); i += AUTHTABLE_CHUNK_SIZE) {
                        var chunk_index = (chunk_start + i) / AUTHTABLE_CHUNK_SIZE;
                        print(@"Verifying chunk: i=$i; i+AUTHTABLE_CHUNK_SIZE=$(i+AUTHTABLE_CHUNK_SIZE); resource_data.length=$(resource_data.length); chunk_start=$chunk_start; chunk_end=$chunk_end; chunk_index=$chunk_index\n");
                        if(!auth_table.verify_chunk(resource_data[i:uint64.min(i+AUTHTABLE_CHUNK_SIZE, resource_data.length)], chunk_index)) {
                            throw new IOError.INVALID_DATA("Verification of resource data against the auth table failed.");
                        }
                    }
                    return new Bytes(resource_data);
                }).get_data();
            });
        }
    }

}