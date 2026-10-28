module DracinApi
  class Error < StandardError; end
  class MissingApiKey < Error; end
  class Unsupported < Error; end
  class HttpError < Error
    attr_reader :code
    def initialize(code, message = nil)
      @code = code
      super(message || "HTTP #{code}")
    end
  end
end
