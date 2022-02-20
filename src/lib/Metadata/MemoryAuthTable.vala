

namespace Downlink {

    public class MemoryAuthTable : AuthTable {

        private Gee.LinkedList<Bytes> table = new Gee.LinkedList<Bytes>();

        public override void append_chunk_hash(uint8[] hash) {
            table.add(new Bytes(hash));
        }

        public override uint8[] get_chunk_hash(uint64 chunk_index) {
            return table.get((int)chunk_index).get_data();
        }

        public override uint64 get_chunk_count() {
            return table.size;
        }

    }

}