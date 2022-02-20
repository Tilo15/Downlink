using Downlink.Util;

namespace Downlink {

    public const uint64 AUTHTABLE_CHUNK_SIZE = 1024;

    public abstract class AuthTable : Object {

        public abstract void append_chunk_hash(uint8[] hash);

        public abstract uint8[] get_chunk_hash(uint64 chunk_index);

        public abstract uint64 get_chunk_count();

        public bool verify_chunk(uint8[] data, uint64 chunk_index) {
            var hash = new Bytes(Sha256Sum.from_data(data));
            print(@"Checking if hash (at index $chunk_index)\n\t$(base64_encode(hash.get_data())) matches\n\t$(base64_encode(get_chunk_hash(chunk_index)))\n");
            return hash.compare(new Bytes(get_chunk_hash(chunk_index))) == 0;
        }

        public void append_chunk_hash_from_data(uint8[] chunk) {
            append_chunk_hash(Sha256Sum.from_data(chunk));
        }

        public void copy_to(AuthTable other) {
            print("Copy\n");
            var count = get_chunk_count();
            for(var i = 0; i < count; i++) {
                var hash = get_chunk_hash(i);
                other.append_chunk_hash(hash);
            }
        }

        public uint8[] serialise() {
            return build_bytes(stream => {
                var count = get_chunk_count();
                stream.put_uint64(count);
                for(var i = 0; i < count; i++) {
                    var hash = get_chunk_hash(i);
                    stream.write(hash);
                }
            });
        }
        
    }

}