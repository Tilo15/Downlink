

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
            var metadata = get_fs_metadata(key);
            if(metadata == null) {
                metadata = get_metadata();
                save_metadata(metadata);
            }
            return metadata;
        }

        public void add_metadata(Metadata metadata) throws IOError, Error {
            save_metadata(metadata);
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
            //  if(metadata.expiry.difference(new DateTime.now_utc()) < 0) {
            //      // Expired
            //      file.delete();
            //      return null;
            //  }
            return metadata;
        }

        public bool has_resource(ResourceIdentifier resource) {
            var file = GLib.File.new_for_path(get_resource_path(resource));
            return file.query_exists();
        }

        public bool has_full_resource(ResourceIdentifier resource) {
            var file = GLib.File.new_for_path(get_resource_path(resource));
            print("Has full resource?\n");
            if(file.query_exists()) {
                var chunks = get_resource_chunks(resource);
                uint64 position = 0;
                foreach (var chunk in chunks) {
                    if(position < chunk.start) {
                        print("Chunk start is less than chunk start: no\n");
                        return false;
                    }
                    position = chunk.end;
                }
                print(@"Maybe, if $position == $(resource.size)\n");
                return position == resource.size;
            }
            print("Resource path does not exist: no\n");
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
                if(position == end) {
                    break;
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

        public ResourceIdentifier add_resource(DataInputStream stream) throws Error, IOError {
            FileIOStream iostream;
            var tempfile = GLib.File.new_tmp("downlink-fsstore-resource-temp-XXXXXX.reschunk", out iostream);

            var authtable = new MemoryAuthTable();
            var size = 0;
            while(true) {
                var chunk = Util.read_exact_bytes_or_eof(stream, AUTHTABLE_CHUNK_SIZE);
                if(chunk.length != 0) {
                    authtable.append_chunk_hash_from_data(chunk);
                    iostream.output_stream.write(chunk);
                }
                size += chunk.length;
                if(chunk.length < AUTHTABLE_CHUNK_SIZE) {
                    break;
                }
            }

            var identifier = new ResourceIdentifier(authtable, size);
            ensure_resource_path(identifier);
            var file = GLib.File.new_for_path(@"$(get_resource_path(identifier))/0.$size.reschunk");
            if(file.query_exists()) {
                file.delete();
            }
            tempfile.move(file, FileCopyFlags.ALL_METADATA);

            var authtable_file = GLib.File.new_for_path(get_auth_table_path(identifier));
            if(authtable_file.query_exists()) {
                authtable_file.delete();
            }
            var fs_authtable = new FilesystemAuthTable(authtable_file.create_readwrite(FileCreateFlags.REPLACE_DESTINATION));
            authtable.copy_to(fs_authtable);

            return identifier;
        }

        public AuthTable read_auth_table(ResourceIdentifier resource, ReadAuthTableDelegate? get_auth_table = null) throws Error, IOError {
            var file = GLib.File.new_for_path(get_auth_table_path(resource));
            if(file.query_exists()) {
                return new FilesystemAuthTable(file.open_readwrite());
            }
            ensure_resource_path(resource);
            var table = get_auth_table();
            var fs_table = new FilesystemAuthTable(file.create_readwrite(FileCreateFlags.REPLACE_DESTINATION));
            table.copy_to(fs_table);
            return fs_table;
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

        private GLib.List<ResourceChunk> get_resource_chunks(ResourceIdentifier resource) {
            var resource_path = get_resource_path(resource);
            var chunks = new GLib.List<ResourceChunk>();
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
                    chunks.append(new ResourceChunk(@"$resource_path/$filename", uint64.parse(parts[0]), uint64.parse(parts[1])));
                }
            }
            chunks.sort((a, b) => (int)(a.start - b.start));
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

        private void save_metadata(Metadata metadata) throws IOError, Error{
            var path = get_metadata_path(metadata.publisher);
            var file = GLib.File.new_for_path(path);
            if(file.query_exists()) {
                file.delete();
            }
            var stream = file.create(FileCreateFlags.REPLACE_DESTINATION);
            stream.write(metadata.to_bytes());
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

            public uint8[] read(uint64 r_start, uint64 r_end) throws IOError, Error requires (r_start >= start && r_end <= end) {
                var file = GLib.File.new_for_path(file_path);
                var stream = file.read();
                stream.seek((int64)(r_start - start), SeekType.SET);
                var data = Util.read_exact_bytes_or_eof(stream, r_end - r_start);
                return data;
            }
        }
    }
}