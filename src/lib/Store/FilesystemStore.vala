

namespace Downlink {

    public class FilesystemStore : Store, Object {

        public string store_path { get; set; }

        public FilesystemStore(string store_path) {
            this.store_path = store_path;
        }

        public bool has_metadata(PublisherKey key) {
            try { 
                var metadata = get_fs_metadata(key);
                return metadata != null;
            }
            catch {
                return false;
            }
        }

        public Metadata read_metadata(PublisherKey key, ReadMetadataDelegate? get_metadata = null) throws Error, IOError {
            return get_fs_metadata(key) ?? get_metadata();
        }

        private Metadata? get_fs_metadata (PublisherKey key) throws Error, IOError {
            var file = GLib.File.new_for_path(get_metadata_path(key));
            if(!file.query_exists()) {
                return null;
            }
            var stream = file.read();
            stream.seek(0, SeekType.END);
            var size = stream.tell();
            stream.seek(0, SeekType.SET);
            var data = new uint8[size];
            stream.read(data);
            var metadata = new Metadata.from_bytes(data, key);
            if(metadata.expiry.difference(new DateTime.now_utc()) > 0) {
                // Expired
                file.delete();
                return null;
            }
            return metadata;
        }

        public bool has_resource(ResourceIdentifier resource) {
            var file = GLib.File.new_for_path(get_resource_path(resource));
            return file.query_exists();
        }

        public bool has_full_resource(ResourceIdentifier resource) {
            var file = GLib.File.new_for_path(get_resource_path(resource));
            if(file.query_exists()) {
                var chunks = get_resource_chunks(resource);
                uint64 position = 0;
                foreach (var chunk in chunks) {
                    if(position != chunk.start) {
                        return false;
                    }
                    position = chunk.end;
                }
                return position == resource.size;
            }
            return false;
        }

        public uint8[] read_resource(ResourceIdentifier resource, uint64 start, uint64 end, ReadResourceDelegate? get_resource = null) throws Error, IOError {
            ensure_resource_path(resource);
            var chunks = get_resource_chunks(resource);

            var composer = new LibPeer.Util.ByteComposer();
            uint64 position = start;
            foreach (var chunk in chunks) {
                if(chunk.start > position) {
                    var chunk_data = get_resource(position, uint64.min(chunk.start, end));
                    save_chunk(resource, position, chunk_data);
                    position += chunk_data.length;
                    composer.add_byte_array(chunk_data);
                }
                if(chunk.end > position && chunk.start <= position) {
                    var chunk_data = chunk.read(position, uint64.min(end, chunk.end));
                    composer.add_byte_array(chunk_data);
                    position += chunk_data.length;
                }
            }
            if(position < end) {
                var chunk_data = get_resource(position, end);
                save_chunk(resource, position, chunk_data);
                position += chunk_data.length;
                composer.add_byte_array(chunk_data);
            }

            return composer.to_byte_array();
        }

        public AuthTable read_auth_table(ResourceIdentifier resource, ReadAuthTableDelegate? get_auth_table = null) throws Error, IOError {
            var file = GLib.File.new_for_path(get_auth_table_path(resource));
            if(file.query_exists()) {
                return new FilesystemAuthTable(file.open_readwrite());
            }
            return get_auth_table();
        }

        private string get_metadata_path(PublisherKey key) {
            return @"$store_path/$(key.identifier).metadata";
        }

        private void ensure_resource_path(ResourceIdentifier resource) throws Error, IOError {
            var folder = GLib.File.new_for_path(get_resource_path(resource));
            if(!folder.query_exists()) {
                folder.make_directory();
            }
        }

        private string get_resource_path(ResourceIdentifier resource) {
            return @"$store_path/$resource";
        }

        private string get_auth_table_path(ResourceIdentifier resource) {
            return @"$(get_resource_path(resource))/authtable";
        }

        private Gee.LinkedList<ResourceChunk> get_resource_chunks(ResourceIdentifier resource) {
            var resource_path = get_resource_path(resource);
            var chunks = new Gee.LinkedList<ResourceChunk>();
            Dir dir;
            try {
                dir = Dir.open(resource_path);
            }
            catch {
                return chunks;
            }
            string? filename;
            while(null != (filename = dir.read_name())) {
                var parts = filename.split(".");
                if(parts.length == 3 && parts[2] == "reschunk") {
                    chunks.add(new ResourceChunk(@"$resource_path/$filename", uint64.parse(parts[0]), uint64.parse(parts[1])));
                }
            }
            chunks.order_by(c => (int)c.start);
            return chunks;
        }

        private void save_chunk(ResourceIdentifier resource, uint64 start, uint8[] data) throws IOError, Error {
            var resource_path = get_resource_path(resource);
            var file = GLib.File.new_for_path(@"$resource_path/$start.$(data.length + start).reschunk");
            if(file.query_exists()) {
                file.delete();
            }
            var stream = file.create(FileCreateFlags.REPLACE_DESTINATION);
            stream.write(data);
            stream.flush();
            stream.close();
        }

        private class ResourceChunk {
            public uint64 start { get; set; }
            public uint64 end { get; set; }
            public string file_path { get; set; }
            public ResourceChunk(string path, uint64 start, uint64 end) {
                this.start = start;
                this.end = end;
                file_path = path;
            }

            public uint8[] read(uint64 start, uint64 end) throws IOError, Error requires (start >= this.start && end <= this.end) {
                var file = GLib.File.new_for_path(file_path);
                var stream = file.read();
                var data = new uint8[end - start];
                stream.seek((int64)(start - this.start), SeekType.SET);
                stream.read(data);
                return data;
            }
        }
    }
}