using LibPeer.Protocols.Mx2;
using LibPeer.Protocols.Stp;
using LibPeer.Protocols.Stp.Streams;
using LibPeer.Util;

namespace Downlink {

    public delegate void CommandResponseHandler(DataInputStream stream) throws IOError, Error;

    public class DownlinkPeer : Object {

        public InstanceReference instance_reference { get; private set; }

        protected DataInputStream reply_stream { get; set; }
        protected DataOutputStream command_stream { get; set; }
        public bool is_mirror { get; set; }
        public bool is_ready { get; private set; default = false; }

        public signal void peer_ready(DownlinkPeer peer);

        protected CommandStatus issue_command(string command, string arguments, CommandResponseHandler callback) throws IOError, Error requires (is_ready) {

            lock(command_stream) {
                print(@"Issue: $command $arguments\n");
                command_stream.put_string(@"$command $arguments\n");
                command_stream.flush();
                
                print("Waiting for reply...\n");
                var response_code = reply_stream.read_byte();
                if(response_code != 0) {
                    return (CommandStatus)response_code;
                }

                callback(reply_stream);
            }

            return CommandStatus.OK;
        }

        public DownlinkPeer(InstanceReference instance_ref) {
            instance_reference = instance_ref;
        }

        public void establish_communication(StreamTransmissionProtocol stp) throws IOError, Error {
            stp.initialise_stream(instance_reference).established.connect(initial_stream_established);
        }

        private void initial_stream_established(Negotiation nego, StpOutputStream stream) {
            stream.reply.connect(reply_stream_established);
            command_stream = new DataOutputStream(stream);
            command_stream.write(new uint8[] {'I'});
            command_stream.flush();
            print("Command stream established\n");
        }

        private void reply_stream_established(StpInputStream stream) {
            reply_stream = new DataInputStream(stream);
            print("Reply stream established\n");
            this.is_ready = true;
            peer_ready(this);
        }

        public uint8[] get_resource_part(ResourceIdentifier identifier, uint64 start, uint64 end) throws IOError, Error {           
            uint8[] buffer = new uint8[0];
            var result = issue_command("GET", @"$identifier $start $end", s => {
                var actual = s.read_uint64();
                buffer = new uint8[actual];
                s.read(buffer);
            });
            if(result == CommandStatus.OK) {
                return buffer;
            }
            throw result.to_error();
        }

        public void get_resource(ResourceIdentifier identifier, Func<Bytes> chunk_handler) throws IOError, Error {
            var result = issue_command("GET", @"$identifier 0 $(identifier.size)", s => {
                var actual = s.read_uint64();
                var read = 0;
                while (read < actual) {
                    var buffer = new uint8[uint64.min(actual - read, 8192)];
                    s.read(buffer);
                    chunk_handler(new Bytes(buffer));
                    read += buffer.length;
                }
            });
            if(result == CommandStatus.OK) {
                return;
            }
            throw result.to_error();
        }

        public AuthTable get_auth_table(ResourceIdentifier identifier) throws IOError, Error {
            var table = new MemoryAuthTable();
            var result = issue_command("AUTH", identifier.to_string(), s => {
                var chunk_count = s.read_uint64();
                var chunk_hash = new uint8[SHA256_SIZE];
                for(uint64 i = 0; i < chunk_count; i++) {
                    s.read(chunk_hash);
                    table.append_chunk_hash(chunk_hash);
                }
            });
            if(result == CommandStatus.OK) {
                return table;
            }
            throw result.to_error();
        }

        public bool probe(ResourceIdentifier identifier) throws IOError, Error {
            var result = issue_command("PROBE", identifier.to_string(), s => {
                var reply_size = s.read_int32();
                // Rerserved for future use
                if(reply_size > 0) {
                    var reply_data = new uint8[reply_size];
                    s.read(reply_data);
                }
            });
            if(result == CommandStatus.OK) {
                return true;
            }
            if(result == CommandStatus.NOT_FOUND) {
                return false;
            }

            throw result.to_error();
        }

        public Metadata get_metadata(PublisherKey key) throws IOError, Error {
            print("Get metadtat\n");
            var meta_data = new uint8[0];
            var result = issue_command("METADATA", key.identifier, s => {
                var metadata_size = s.read_int32();
                meta_data = new uint8[metadata_size];
                s.read(meta_data);
            });

            if(result == CommandStatus.OK) {
                return new Metadata(meta_data, key);
            }
            throw result.to_error();
        }

    }

}