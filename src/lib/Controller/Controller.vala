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
        private Gee.HashSet<Bytes> resources = new Gee.HashSet<Bytes>(a => a.hash(), (a, b) => a.compare(b) == 0);

        public bool is_mirror { get; private set; }

        public DownlinkController(Store store, PublisherKey[] subscriptions, bool mirror_mode = false) {
            this.store = store;
            is_mirror = mirror_mode;
            initialise("Downlink");
            foreach (var subscription in subscriptions) {
                peer_groups.set(subscription, new PeerGroup());
                var res_id = get_mirror_resource_identifier(subscription);
                resources.add(res_id);
                search_for_resource_peer(res_id, new Gdp.Challenge(s => {return s;}), subscription.public_key);
                if(!is_mirror) {
                    res_id = get_comrade_resource_identifier(subscription);
                    resources.add(res_id);
                    search_for_resource_peer(res_id, new Gdp.Challenge(s => {return s;}), subscription.public_key);
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

        protected override void on_challenge(Bytes resource_identifier, Gdp.Challenge challenge) {
            if(resources.contains(resource_identifier)) {
                // TODO make more robust
                challenge.complete(challenge.challenge_blob);
            }
        }
        
        protected override void on_query_answer (Gdp.Answer answer) {
            var key = new PublisherKey(answer.query_summary.private_blob);
            var mirror_id = get_mirror_resource_identifier(key);
            var comrade_id = get_comrade_resource_identifier(key);
            if(mirror_id.compare(answer.query_summary.resource_hash) == 0) {
                contact_mirror(peer_groups.get(key), answer);
            }
            if(comrade_id.compare(answer.query_summary.resource_hash) == 0) {
                contact_comrade(peer_groups.get(key), answer);
            }
        }

        private void contact_mirror(PeerGroup group, Gdp.Answer answer) {
            if(peers.has_key(answer.instance_reference)) {
                group.add_mirror(peers.get(answer.instance_reference));
                return;
            }

            var peer = new Peer(answer.instance_reference);
            peer.peer_ready.connect(group.add_mirror);
            peers.set(answer.instance_reference, peer);
            inquire(answer);
        }

        private void contact_comrade(PeerGroup group, Gdp.Answer answer) {
            if(peers.has_key(answer.instance_reference)) {
                group.add_mirror(peers.get(answer.instance_reference));
                return;
            }

            var peer = new Peer(answer.instance_reference);
            peer.peer_ready.connect(group.add_comrade);
            peers.set(answer.instance_reference, peer);
            inquire(answer);
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
            return new Bytes(Sha512Sum.from_data(key.public_key));
        }

        private static Bytes get_mirror_resource_identifier(PublisherKey key) {
            return new Bytes(Sha512Sum.from_data(Sha512Sum.from_data(key.public_key)));
        }

        private bool has_key(PublisherKey key) {
            return peer_groups.has_key(key);
        }

        private delegate T PeerCallback<T>(Peer peer) throws IOError, Error;

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