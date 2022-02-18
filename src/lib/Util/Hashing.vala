

namespace Downlink.Util {

    public const int SHA256_SIZE = 32;
    public const int SHA512_SIZE = 64;

    public class Sha256Sum {

        private Checksum checksum = new Checksum (ChecksumType.SHA256);
        
        public void update(uint8[] data, size_t? size = null) {
            checksum.update(data, size ?? data.length);
        }

        public uint8[] digest() {
            var hash = new uint8[SHA256_SIZE];
            size_t size = SHA256_SIZE;
            checksum.get_digest(hash, ref size);
            return hash;
        }

        public static uint8[] from_data(uint8[] data) {
            var cs = new Sha256Sum();
            cs.update(data);
            return cs.digest();
        }
    }

    public class Sha512Sum {

        private Checksum checksum = new Checksum (ChecksumType.SHA512);
        
        public void update(uint8[] data, size_t? size = null) {
            checksum.update(data, size ?? data.length);
        }

        public uint8[] digest() {
            var hash = new uint8[SHA512_SIZE];
            size_t size = SHA512_SIZE;
            checksum.get_digest(hash, ref size);
            return hash;
        }

        public static uint8[] from_data(uint8[] data) {
            var cs = new Sha512Sum();
            cs.update(data);
            return cs.digest();
        }
    }

}