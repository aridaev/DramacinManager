require "net/http"

module DracinApi
  # HTTP GET JSON bersama untuk hub (api.dramabuzz.sbs) dan host per-provider (*.goodbos.online).
  module Http
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    module_function

    def get_json(url, params: {}, headers: {})
      uri = URI.parse(url)
      if params.present?
        existing = uri.query ? URI.decode_www_form(uri.query) : []
        uri.query = URI.encode_www_form(existing + params.compact.to_a)
      end

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = "DracinManager/1.0"
      headers.each { |k, v| request[k] = v if v.present? }

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) { |http| http.request(request) }

      body = response.body.to_s
      unless response.is_a?(Net::HTTPSuccess)
        detail = (JSON.parse(body)["error"] rescue nil)
        raise HttpError.new(response.code.to_i, [ I18n.t("dracin_api.errors.http_error", code: response.code), detail ].compact.join(" — "))
      end

      JSON.parse(body)
    rescue JSON::ParserError
      raise Error, I18n.t("dracin_api.errors.invalid_json")
    rescue Net::OpenTimeout, Net::ReadTimeout
      raise Error, I18n.t("dracin_api.errors.timeout")
    rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError
      raise Error, I18n.t("dracin_api.errors.connection", host: uri&.host || url)
    end
  end
end
