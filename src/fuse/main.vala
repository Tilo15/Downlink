using LibPeer.Util;
using Downlink;

namespace DownlinkFuse {

    //  const string publisher_key = "VMd5qX21C4tIBQ6pI/Ug94qnqiglyb0Ert4bgz9OCuw=";
    //  const string mount_name = "my-downlink";
    //  const string cache_location = "test_local";

    static DownlinkController controller;
    static ConcurrentHashMap<string, PublisherKey> mounts;
    static Store store;

    static int main(string[] argv) {
        var config_path = "/etc/downlink/downlink.config";
        if(argv.length > 1) {
            config_path = argv[1];
            printerr(@"Using $(config_path) as configuration file.\n");
        }

        DownlinkConfig config;
        try {
            config = new DownlinkConfig(config_path);
        }
        catch (Error e) {
            printerr(@"Failed to read configuration: $(e.message)\n");
            return e.code;
        }

        store = new FilesystemStore(config.cache_path);
        mounts = new ConcurrentHashMap<string, PublisherKey>();

        foreach (var mount in config.mounts) {
            mounts.set(mount.name, new PublisherKey.from_string(mount.publisher_key));
        }
        
        controller = new DownlinkController(store, mounts.values.to_array());

        //  printerr("Pre-caching metadata...\n");
        //  foreach (var mount in mounts) {
        //      printerr(@"Pre-caching metadata for '$(mount.key)'.\n");
        //      controller.get_metadata(mount.value);
        //  }
        //  printerr("Ready\n");

        var ops = Fuse.Operations();
        ops.open = (path, ref fi) => 0;
        ops.getattr = get_attributes;
        ops.readdir = get_dir;
        ops.read = read_file;
        ops.getxattr = get_xattr;

        string[] fuse_args = new string[] {argv[0], "-f", config.mount_point};
        //  if(argv.length > 2) {
        //      fuse_args = new string[argv.length -1];
        //      var fi = 0;
        //      for(int i = 0; i < argv.length; i++) {
        //          if(i != 1) {
        //              fuse_args[fi] = argv[i];
        //          }
        //          fi++;
        //      }
        //  }
    
        return Fuse.main(fuse_args, ops, null);
    }

    void set_dir_attributes(Posix.Stat* stat, int size) {
        stat.st_mode = Posix.S_IFDIR | 0555;
        stat.st_nlink = 2;
    }

    void set_file_attributes(Posix.Stat* stat, int size) {
        stat.st_mode = Posix.S_IFREG | 0444;
        stat.st_nlink = 1;
        stat.st_size = size;
    }

    int error_to_posix(Error e) {
        if(e is IOError) {
            switch (e.code) {
                case IOError.INVALID_ARGUMENT:
                    return -Posix.EINVAL;
                case IOError.INVALID_DATA:
                    return -Posix.EBADF;
                case IOError.NETWORK_UNREACHABLE:
                    return -Posix.ENETUNREACH;
                case IOError.FAILED:
                    return -121;
                case IOError.NOT_FOUND:
                    return -Posix.EAGAIN;
            }
        }
        return -Posix.EIO;
    }

    delegate int FileHandler(Downlink.File file, Metadata metadata);
    delegate int FolderHandler(Folder folder, Metadata metadata);

    int handle_path(string path, FileHandler handle_file, FolderHandler handle_folder, int not_found_code = -Posix.ENOENT) {
        var parts = path.split("/");
        var mount_name = parts[1];
        if(mounts.has_key(mount_name)) {
            Metadata metadata;
            print("Tryna get metadata\n");
            try {
                metadata = controller.get_metadata(mounts.get(mount_name));
            }
            catch (Error e){
                printerr(@"[DOWNLINK] Error handling path '$path': $(e.message)\n");
                return error_to_posix(e);
            }
            Folder folder = metadata.root;
            print(@"About to iterate over root of mount (path=$path)\n");
            for(var i = 2; i < parts.length; i++) {
                print(@"On part '$(parts[i])'\n");
                if(folder.folders.has_key(parts[i])) {
                    print("It's a folder\n");
                    folder = folder.folders.get(parts[i]);
                    continue;
                }
                else if(i == parts.length - 1 && folder.files.has_key(parts[i])) {
                    print("It's a file, and the last part of the path\n");
                    var file = folder.files.get(parts[i]);
                    return handle_file(file, metadata);
                }
                else {
                    print("Couldn't find it!\n");
                    // Not found
                    return not_found_code;
                }
            }
            print("Handle folder\n");
            return handle_folder(folder, metadata);
        }
        // Not found
        return not_found_code;
    }

    static int get_attributes(string path, Posix.Stat* stat) {
        print("Get attributes\n");
        if(path == "/") {
            print("Attributes for root\n");
            set_dir_attributes(stat, mounts.size);
            return 0;
        }
        else {
            return handle_path(
                path,
                file => {
                    print("Attributes for file\n");
                    set_file_attributes(stat, (int)file.resource.size);
                    return 0;
                },
                folder => {
                    print("Attributes for folder\n");
                    set_dir_attributes(stat, folder.files.size + folder.folders.size);
                    return 0;
                });
        }
    }

    static int get_dir(string path, void* buf, Fuse.FillDir filler, Posix.off_t offset, ref Fuse.FileInfo file_info) {
        filler(buf, ".", null, 0);
        filler(buf, "..", null, 0);
        if(path == "/") {
            foreach (var mount in mounts) {
                filler(buf, mount.key, null, 0);
            }
            return 0;
        }
        else {
            return handle_path(
                path,
                file => {
                    return -Posix.ENOTDIR;
                },
                folder => {
                    print("Handling listing of folder\n");
                    foreach(var subfolder in folder.folders){
                        print(@"Subfolder '$(subfolder.key)'\n");
                        filler(buf, subfolder.key, null, 0);
                    }
                    foreach(var file in folder.files) {
                        print(@"File '$(file.key)'\n");
                        filler(buf, file.key, null, 0);
                    }
                    return 0;
                });
        }
    }

    static int read_file(string path, char* buffer, size_t size, Posix.off_t offset, ref Fuse.FileInfo file_info) {
        if(path == "/") {
            return -Posix.EISDIR;
        }
        else {
            return handle_path(
                path,
                (file, metadata) => {
                    try {
                        var data = controller.get_resource(metadata.publisher, file.resource, offset, uint64.min(offset+size, file.resource.size));
                        Memory.copy(buffer, data.copy(), data.length);
                        return data.length;
                    }
                    catch (Error e) {
                        printerr(@"[DOWNLINK] Error reading resource '$(file.resource)' as path '$path': $(e.message)\n");
                        return error_to_posix(e);
                    }
                },
                folder => {
                    return -Posix.EISDIR;
                });
        }
    }

    static int get_xattr(string path, string name, char* value, size_t size) {
        print(@"Getxattr: $(path) $(name)\n");
        if(name == "downlink-remote") {
            var result = "false".data;
            if(path.split("/").length > 2) {
                result = "true".data;
            }
            Memory.copy(value, result, int.min(result.length, (int)size));
            return result.length;
        }

        if(name == "downlink-cached") {
            if(path.split("/").length < 3) {
                return -Posix.ENOTSUP;
            }

            return handle_path(path, (file, metadata) => {
                var available = store.bytes_available(file.resource);
                var result = available.to_string().data;
                Memory.copy(value, result, int.min(result.length, (int)size));
                return result.length;
            },
            folder => {
                return -Posix.ENOTSUP;
            });
        }

        if(name == "downlink-complete") {
            if(path.split("/").length < 3) {
                return -Posix.ENOTSUP;
            }

            return handle_path(path, (file, metadata) => {
                var available = store.has_full_resource(file.resource);
                var result = available.to_string().data;
                Memory.copy(value, result, int.min(result.length, (int)size));
                return result.length;
            },
            folder => {
                return -Posix.ENOTSUP;
            });
        }
        return -Posix.ENOTSUP;
    }

}