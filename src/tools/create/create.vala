
namespace DownlinkCreate {

    public static int main(string[] args) {

        if(args.length < 4) {
            printerr("Usage: downlink-create <input dir> <publishing key> <output>\nCreates or adds to a store with metadata servable with downlink-mirror.\n");
        }

        var output = File.new_for_commandline_arg(args[3]);
        if(!output.query_exists()) {
            output.make_directory();
        }

        var key_file = File.new_for_commandline_arg(args[2]);
        var stream = new DataInputStream(key_file.read());
        var key = new Downlink.PublishingKey.from_string(stream.read_line());

        var store = new Downlink.FilesystemStore(args[3]);

        var metadata = new Downlink.Metadata(new DateTime.now_utc().add_days(2));
        metadata.root = build_tree(args[1], args[1], store);

        printerr("Finalising metadata\n");
        metadata.publish(key);
        store.add_metadata(metadata);
        printerr("Complete!\n");

        return 0;

    }

    private Downlink.Folder build_tree(string path, string root_path, Downlink.Store store) {
        var metadata = new Downlink.Folder(Path.get_basename(path));
        var dir = Dir.open(path);
        string? child;
        while(null != (child = dir.read_name())) {
            var full_path = @"$path/$child";
            var file = File.new_for_path(full_path);
            var relative_path = path.substring(root_path.length) + "/" + child;
            if(file.query_file_type(FileQueryInfoFlags.NONE) == FileType.DIRECTORY) {
                printerr(@"Adding directory '$relative_path'\n");
                metadata.folders.set(relative_path, build_tree(full_path, root_path, store));
            }
            else {
                printerr(@"Adding file '$relative_path'\n");
                var identifier = store.add_resource(new DataInputStream(file.open_readwrite().input_stream));
                metadata.files.set(relative_path, new Downlink.File(child, identifier));
            }
        }
        return metadata;
    }



}