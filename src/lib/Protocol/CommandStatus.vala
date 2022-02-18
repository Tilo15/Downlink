
namespace Downlink {

    public enum CommandStatus {
        OK = 0,
        NOT_FOUND = 1,
        OUT_OF_RANGE = 2,
        NO_METADATA = 3,
        INTERNAL_ERROR = 4;

        public IOError to_error() {
            switch (this) {
                case NOT_FOUND:
                    return new IOError.NOT_FOUND("The specified resource could not be found.");
                case OUT_OF_RANGE:
                    return new IOError.INVALID_ARGUMENT("The specified locations are out of range.");    
                case NO_METADATA:
                    return new IOError.NOT_FOUND("The remote peer does not have a copy of the requested metadata.");
                case INTERNAL_ERROR:
                    return new IOError.FAILED("There remote peer encountered an internal error while processing our request.");
                default:
                    return new IOError.FAILED("There was an error determining the nature of another error.");
            }
        }
    }

}