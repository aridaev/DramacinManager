module DracinApi
  # Klien untuk hub DracinAPI (https://api.dramabuzz.sbs).
  # Hub hanya menyediakan daftar + status platform; endpoint konten tiap provider
  # berada di host masing-masing (lihat DracinApi::Adapters).
  class Client
    DEFAULT_BASE_URL = "https://api.dramabuzz.sbs".freeze

    attr_reader :base_url, :api_key

    def self.from_settings
      from_source(ApiSource.default) || new(base_url: Setting.dracin_api_base_url, api_key: Setting.dracin_api_key)
    end

    def self.from_source(source)
      return nil if source.nil?
      new(base_url: source.base_url, api_key: source.api_key, source: source)
    end

    attr_reader :source

    def initialize(base_url: DEFAULT_BASE_URL, api_key: nil, source: nil)
      @base_url = (base_url.presence || DEFAULT_BASE_URL).chomp("/")
      @api_key = api_key.presence
      @source = source
    end

    def configured? = source ? source.configured? : api_key.present?

    # GET /api/status?key=... → { success, timestamp, summary: { total, has_api, no_api }, platforms: [...] }
    def status
      raise MissingApiKey, I18n.t("dracin_api.errors.missing_api_key") unless configured?
      return Http.get_json("#{base_url}/api/status", params: { key: api_key }) if source.nil?
      url = source.status_url or raise Error, "status_path kosong"
      # Hub DracinAPI memakai ?key=; sumber lain mengikuti auth_mode-nya.
      params = source.auth_mode == "header_x_token" && source.slug == "dracinapi" ? { key: api_key } : source.auth_params
      Http.get_json(url, params: params, headers: source.auth_headers)
    end
  end
end
