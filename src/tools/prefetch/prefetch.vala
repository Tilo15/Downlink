
using Linux;

namespace DownlinkPrefetch {

    private const string DOWNLINK_REMOTE = "xattr-sys::downlink-remote";
    private const string DOWNLINK_CACHED = "xattr-sys::downlink-cached";
    private const string DOWNLINK_COMPLETE = "xattr-sys::downlink-complete";
    private const string FILE_SIZE = FileAttribute.STANDARD_SIZE;

    public static int main(string[] args) {

        var options = new PrefetchCliArgs(args);
        update_winsize();

        if(options.invalid) {
            printerr("Usage: downlink-prefetch <path>\nPrefetches a file from the Downlink network\n");
            printerr("Additional options:\n\t-p\tprint prefetch progress to stdout.\n\t-c <size>\tchunk size for prefetching in bytes (default 1048576)\n\n");
            return -1;
        }

        var path = File.new_for_path(options.file);
        FileInfo file_info = null;

        try {
            file_info = path.query_info(@"$DOWNLINK_REMOTE,$DOWNLINK_CACHED,$DOWNLINK_COMPLETE,$FILE_SIZE", FileQueryInfoFlags.NONE);
        }
        catch {
            printerr(@"Failed to get information for path $(options.file)\n");
            return -2;
        }

        if(file_info.get_attribute_string(DOWNLINK_REMOTE) != "true") {
            printerr("The provided path does not point to a downlink remote file\n");
            return -3;
        }

        if(file_info.get_attribute_string(DOWNLINK_COMPLETE) == "true") {
            if(options.show_progress) {
                printerr("The provided path is already fully cached locally. Nothing to do.\n");
            }

            return 0;
        }

        var target = file_info.get_size();
        var cached = int64.parse(file_info.get_attribute_string(DOWNLINK_CACHED));

        var label = @"Prefetching $(path.get_basename())";

        try {
            var stream = path.read();
            var buffer = new uint8[options.chunk_size];
            while(target != cached) {
                if(options.show_progress)
                    display_progress(cached, target, label);
                
                stream.read(buffer);
                var cached_str = path.query_info(DOWNLINK_CACHED, FileQueryInfoFlags.NONE).get_attribute_string(DOWNLINK_CACHED);
                cached = int64.parse(cached_str);
            }
            stream.close();
            if(options.show_progress) {
                display_progress(cached, target, label);
                print("\n");
            }
        }
        catch {
            printerr("\nAn error occurred while attempting to prefetch the requested file\n");
            return -3;
        }


        return 0;

    }

    private static int cols = 0;

    private bool update_winsize() {
        winsize win_size;
        Posix.ioctl(Posix.STDOUT_FILENO, Termios.TIOCGWINSZ, out win_size);
        var result = cols != win_size.ws_col;
        cols = win_size.ws_col;
        return result;
    }

    private void display_progress(int64 current, int64 target, string label) {
        if(update_winsize()) {
            print("\n");
        }

        var pbar_size = (cols/2) - 8;
        var label_size = (cols/2) - 2;

        var pbar_fill = (int)((((float)current) / ((float) target)) * pbar_size);
        var small_edge = ((int)((((float)current) / ((float) target)) * pbar_size * 2) % 2) == 0;
        var percentage = (int)((((float)current) / ((float) target)) * 100);
        var pbar_string = "[";

        for(int i = 0; i < pbar_size; i++) {
            if(i >= pbar_fill) {
                pbar_string += " ";
                continue;
            }
            if(i == pbar_fill - 1 && small_edge) {
                pbar_string += "-";
            }
            else {
                pbar_string += "=";
            }
        }
        pbar_string += "]";

        var label_string = label;
        if(label.length > label_size) {
            label_string = label_string.substring(0, label_size - 3);
            label_string += "...";
        }

        while(label_string.length < label_size) {
            label_string += " ";
        }

        print(@"\r$label_string $pbar_string $percentage%");
    }


    private class PrefetchCliArgs {

        public string file = null;
        public int chunk_size = 1048576;
        public bool show_progress = false;

        public bool invalid = false;

        public PrefetchCliArgs(string[] args) {

            if(args.length < 2) {
                printerr("Not enough arguments.\n");
                invalid = true;
                return;
            }

            for(var i = 1; i < args.length; i++) {

                if(args[i].has_prefix("-")) {
                    if(args[i] == "-p") {
                        show_progress = true;
                        continue;
                    }
                    if(args[i] == "-c") {
                        i++;
                        chunk_size = int.parse(args[i]);
                        continue;
                    }

                    printerr(@"Unrecognised option \"$(args[i])\".\n");
                    invalid = true;
                    continue;
                }

                if(file != null) {
                    printerr(@"Too many arguments!\n");
                    invalid = true;
                    continue;

                }

                file = args[i];
            }

        }

    }

}