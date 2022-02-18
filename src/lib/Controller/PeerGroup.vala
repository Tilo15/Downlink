
namespace Downlink {

    internal class PeerGroup {

        private Gee.HashSet<Peer> mirror_peers = new Gee.HashSet<Peer>();
        private Gee.HashSet<Peer> comrade_peers = new Gee.HashSet<Peer>();

        private Gee.HashSet<Peer> recently_used_mirrors = new Gee.HashSet<Peer>();
        private Gee.HashSet<Peer> recently_used_comrades = new Gee.HashSet<Peer>();

        private Cond mirror_cond = Cond();
        private Mutex mirror_mutex = Mutex();

        public void add_mirror(Peer peer) {
            lock(mirror_peers) {
                mirror_peers.add(peer);
                mirror_mutex.lock();
                mirror_cond.broadcast();
                mirror_mutex.unlock();
            }
        }

        public void add_comrade(Peer peer) {
            lock(comrade_peers) {
                comrade_peers.add(peer);
            }
        }

        public int mirror_count() {
            lock(mirror_peers) {
                return mirror_peers.size;
            }
        }

        public int comrade_count() {
            lock(comrade_peers) {
                return comrade_peers.size;
            }
        }

        public Peer get_mirror() {
            lock(mirror_peers) {
                foreach (var peer in mirror_peers) {
                    if(can_use_mirror(peer)) {
                        return peer;
                    }
                }
            }
        }

        public Peer get_comrade() {
            lock(comrade_peers) {
                foreach (var peer in comrade_peers) {
                    if(can_use_mirror(peer)) {
                        return peer;
                    }
                }
            }
        }

        public void wait_for_mirror() {
            mirror_mutex.lock();
            mirror_cond.wait(mirror_mutex);
            mirror_mutex.unlock();
        }

        private bool can_use_mirror(Peer peer) {
            lock(recently_used_mirrors) {
                if(recently_used_mirrors.size == mirror_peers.size) {
                    recently_used_mirrors.clear();
                }
                if(recently_used_mirrors.contains(peer)) {
                    return false;
                }
                recently_used_mirrors.add(peer);
                return true;
            }
        }

        private bool can_use_comrade(Peer peer) {
            lock(recently_used_comrades) {
                if(recently_used_comrades.size == comrade_peers.size) {
                    recently_used_comrades.clear();
                }
                if(recently_used_comrades.contains(peer)) {
                    return false;
                }
                recently_used_comrades.add(peer);
                return true;
            }
        }

    }

}