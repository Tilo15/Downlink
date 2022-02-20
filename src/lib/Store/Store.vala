
namespace Downlink {

    public interface Store : Object {

        public delegate uint8[] ReadResourceDelegate(uint64 start, uint64 end) throws Error, IOError;
        public delegate Metadata ReadMetadataDelegate() throws Error, IOError;
        public delegate AuthTable ReadAuthTableDelegate() throws Error, IOError;

        public abstract bool has_metadata(PublisherKey key);

        public abstract Metadata read_metadata(PublisherKey key, ReadMetadataDelegate? get_metadata = null) throws Error, IOError;

        public abstract void add_metadata(Metadata metadata) throws IOError, Error;

        public abstract bool has_resource(ResourceIdentifier resource);

        public abstract bool has_full_resource(ResourceIdentifier resource);

        public abstract uint8[] read_resource(ResourceIdentifier resource, uint64 start, uint64 end, ReadResourceDelegate? get_resource = null) throws Error, IOError;

        public abstract void add_resource(DataInputStream stream) throws IOError, Error ;

        public abstract AuthTable read_auth_table(ResourceIdentifier resource, ReadAuthTableDelegate? get_auth_table = null) throws Error, IOError;

        public bool try_read_metadata(out Metadata metadata, PublisherKey key, ReadMetadataDelegate? get_metadata = null) {
            try {
                metadata = read_metadata(key, get_metadata);
                return true;
            }
            catch {
                return false;
            }
        }

        public bool try_read_resource(out uint8[] data, ResourceIdentifier resource, uint64 start, uint64 end, ReadResourceDelegate? get_resource = null) {
            try {
                data = read_resource(resource, start, end, get_resource);
                return true;
            }
            catch {
                return false;
            }
        }

        public bool try_read_auth_table(out AuthTable auth_table, ResourceIdentifier resource, ReadAuthTableDelegate? get_auth_table = null) {
            try {
                auth_table = read_auth_table(resource, get_auth_table);
                return true;
            }
            catch {
                return false;
            }
        }

    }

}