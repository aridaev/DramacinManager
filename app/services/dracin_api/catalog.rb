module DracinApi
  # Lapisan di atas adapter per-provider: normalisasi ringan + cache. Semua data berasal dari API;
  # jika API gagal, error DracinApi::Error dilempar ke controller (tidak ada data contoh).
  class Catalog
    Drama   = Struct.new(:provider, :id, :title, :cover, :synopsis, :genres, :language, :episodes, :rating, :year, :status, keyword_init: true)
    Episode = Struct.new(:number, :title, :thumbnail, :duration, :locked, :payload, keyword_init: true)
    # sources: [ { label: "720p", url: } ] — semua varian kualitas yang bisa dipilih pemutar. url = varian default.
    # proxied: CDN tanpa CORS / menolak Referer ? HLS diputar lewat Template::V1::StreamsController.
    Stream  = Struct.new(:url, :format, :quality, :sources, :subtitles, :episode, :cookies, :proxied, keyword_init: true)
    Section = Struct.new(:title, :items, keyword_init: true)
    Page    = Struct.new(:items, :page, :has_more, keyword_init: true)

    CACHE_TTL = 30.minutes
    PLAY_TTL  = 2.minutes # URL video sering ber-signature (auth_key) dan kedaluwarsa cepat
    RACE_TTL  = 20.seconds # saat cache kedaluwarsa, request lain tetap dapat nilai lama selama satu request memperbarui

    attr_reader :provider

    def self.for(provider, lang: I18n.locale)
      new(provider, DracinApi::Adapters.for(provider, lang: lang.to_s), lang: lang.to_s)
    end

    def initialize(provider, adapter, lang: "en")
      @provider = provider
      @adapter = adapter
      @lang = lang
    end

    def slug = provider.slug
    def supported? = @adapter.present?

    def home
      fetch("home") do |a|
        a.home.each { |s| s.items = clean(s.items) }.reject { |s| s.items.empty? }
      end
    end

    def search(keyword, page: 1)
      fetch("search", keyword, page) { |a| a.search(keyword, page: page).tap { |pg| pg.items = clean(pg.items) } }
    end

    def genre(type, page: 1)
      # Tiap provider punya skema kategori sendiri; untuk sekarang genre dipetakan ke pencarian kata kunci.
      search(type.to_s.tr("-", " "), page: page)
    end

    def detail(id)
      fetch("detail", id) { |a| clean_genres(a.detail(id)) }
    end

    def episodes(id)
      fetch("episodes", id) { |a| Array(a.episodes(id)).sort_by(&:number) }
    end

    def play(id, episode)
      fetch("play2", id, episode, ttl: PLAY_TTL) do |a|  # key baru: Stream struct bertambah field (proxied)
        a.prime_episodes(id, episodes(id))
        a.play(id, episode)
      end
    end

    private
    def adapter
      @adapter or raise Unsupported, I18n.t("dracin_api.errors.unsupported", provider: provider.name)
    end

    def clean(items)
      Array(items).reject { |d| d.id.blank? || d.title.blank? }.uniq(&:id).each { |d| clean_genres(d) }
    end

    def clean_genres(drama)
      drama.genres = Array(drama.genres).map { |g| g.to_s.strip }.reject { |g| g.blank? || g.parameterize.blank? }.uniq.first(5)
      drama
    end

    STALE_TTL = 6.hours # salinan "basi" dipakai bila upstream gagal/timeout (host *.goodbos.online sering lambat)

    # Adapter boleh menetapkan CACHE_TTL sendiri (hub berkuota seperti Mola memakai TTL jauh lebih panjang).
    def cache_ttl = (@adapter.class.const_defined?(:CACHE_TTL, false) ? @adapter.class::CACHE_TTL : CACHE_TTL)

    def fetch(*key, ttl: cache_ttl)
      ckey = [ "dracin_api", "v2", slug, @lang, *key ]
      Rails.cache.fetch(ckey, expires_in: ttl, race_condition_ttl: RACE_TTL) do
        value, used = with_fallback { |a| yield a }
        Rails.cache.write([ *ckey, "stale" ], value, expires_in: STALE_TTL) unless value.nil?
        Health.ok!(provider, adapter: used) # hanya sumber adapter yang benar-benar berhasil yang dianggap sehat
        value
      end
    rescue DracinApi::Error => e
      Health.fail!(provider, e, adapter: @adapter)
      stale = Rails.cache.read([ *ckey, "stale" ])
      raise if stale.nil?
      Rails.logger.warn("[DracinApi] #{slug} #{key.first}: #{e.message} → pakai cache lama")
      stale
    end

    # Adapter utama error atau hasil kosong → coba adapter cadangan dari hub lain (Adapters.fallback_for).
    # Mengembalikan [nilai, adapter yang dipakai].
    def with_fallback
      value = begin
        yield adapter
      rescue DracinApi::Error => e
        raise unless fallback
        Rails.logger.warn("[DracinApi] #{slug}: #{e.message} → fallback #{fallback.class.name.demodulize}")
        ProviderErrorStat.bump!(provider, ProviderErrorStat::RESCUED)
        Health.source_fail!(provider, e, adapter: adapter) # sumber utama bermasalah walau cadangan menolong
        return [ yield(fallback), fallback ]
      end
      return [ yield(fallback), fallback ] if fallback && (value.nil? || (value.respond_to?(:empty?) && value.empty?))
      [ value, adapter ]
    end

    def fallback
      return @fallback if defined?(@fallback)
      @fallback = DracinApi::Adapters.fallback_for(provider, lang: @lang)
    end
  end
end
