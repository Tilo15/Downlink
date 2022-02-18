using Downlink;


namespace DownlinkMirror {

    public static int main(string[] args) {
    
        if(args.length < 3) {
            printerr("Usage: downlink-mirror <local folder> <publisher key>\n");
            return -1;
        }

        var store_path = args[1];
        var publisher_key = new PublisherKey.from_string(args[2]);

        var store = new FilesystemStore(store_path);
        var controller = new DownlinkController(store, new PublisherKey[] { publisher_key }, true);
        
        controller.join_server_thread();

        return 0;
    }


}
