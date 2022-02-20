using Downlink.Util;

namespace Downlink {

    public class FilesystemAuthTable : AuthTable {

        private FileIOStream stream;
        private uint64 chunks;

        public FilesystemAuthTable(FileIOStream stream) throws Error {
            this.stream = stream;
            stream.seek(0, SeekType.END);
            chunks = stream.tell() / SHA256_SIZE;
        }

        public override void append_chunk_hash(uint8[] hash) {
            lock(stream) {
                stream.seek(0, SeekType.END);
                stream.output_stream.write(hash);
                stream.output_stream.flush();
            }
        }

        public override uint8[] get_chunk_hash(uint64 chunk_index) {
            var hash = new uint8[SHA256_SIZE];
            lock(stream) {
                stream.seek((int64)(chunk_index * SHA256_SIZE), SeekType.SET);
                stream.input_stream.read(hash);
            }
            return hash;
        }

        public override uint64 get_chunk_count() {
            return chunks;
        }

    }

}