module DracinApi
  # Kesehatan provider & sumber API berdasarkan pengalaman nyata (tanpa request tambahan ke upstream):
  #   - Catalog#fetch memanggil Health.ok!/fail! → provider yang gagal FAIL_THRESHOLD kali beruntun disembunyikan dari
  #     situs publik selama jendela mute (backoff 30 mnt → 1 jam → 3 jam), sukses apa pun mereset;
  #   - error yang jelas milik SUMBER (token ditolak, kuota habis, host hub down) langsung menandai ApiSource.unhealthy_until
  #     sehingga semua provider sumber itu ikut disembunyikan (Provider.available) dan pengunjung diarahkan ke provider sehat;
  #   - kuota harian Mola dianggap pulih pada 00:00 UTC (reset harian gateway), token ditolak dicek lagi setelah AUTH_MUTE.
  # Pengecekan terjadwal (rake dracin:health, tiap 6 jam) melengkapi ini dengan status token/kuota/kedaluwarsa per sumber.
  module Health
    FAIL_THRESHOLD = 3
    FAIL_WINDOW = 10.minutes
    MUTES = [ 30.minutes, 1.hour, 3.hours ].freeze
    AUTH_MUTE = 6.hours
    HUB_DOWN_MUTE = 10.minutes
    RATE_MUTE = 5.minutes
    SOURCE_MIN_PROVIDERS = 3 # sumber baru ditandai tidak sehat bila sebanyak ini provider berbeda gagal dalam FAIL_WINDOW
    QUOTA_RE = /quota|kuota|requests_today|daily|harian|limit habis/i
    RATE_RE  = /rate.?limit|too many request|limit (reached|exceeded)/i
    AUTH_RE  = /unauthori[sz]ed|invalid (api.?)?(key|token)|(api.?key|token) (invalid|missing|expired|ditolak|tidak valid|not active)|kedaluwarsa|key (not active|inactive)/i

    module_function

    def ok!(provider, adapter: nil)
      return if provider.nil?
      ProviderErrorStat.bump!(provider, ProviderErrorStat::OK)
      attrs = { last_ok_at: Time.current }
      attrs.merge!(failures_count: 0, mute_level: 0, unavailable_until: nil, last_error: nil) if provider.failures_count.positive? || provider.unavailable_until.present?
      provider.update_columns(attrs)
      # Sukses = bukti sumbernya hidup (termasuk kuota belum habis) → cabut tanda tidak sehat.
      src = source_for(provider, adapter)
      src.update_columns(unhealthy_until: nil, health_note: nil) if src&.unhealthy_until.present?
    rescue StandardError => e
      Rails.logger.warn("[Health] ok! #{provider&.slug}: #{e.class} #{e.message}")
    end

    # Provider gagal total (adapter utama + cadangan). adapter = adapter utama (untuk tahu sumbernya).
    def fail!(provider, error, adapter: nil)
      return if provider.nil?
      now = Time.current
      kind = classify(error)
      ProviderErrorStat.bump!(provider, Failure.kind(error))
      msg = "#{error.class.name.demodulize}: #{error.message}".truncate(250)
      recent = provider.last_error_at.present? && provider.last_error_at > FAIL_WINDOW.ago
      fails = (recent ? provider.failures_count : 0) + 1
      attrs = { failures_count: fails, last_error: msg, last_error_at: now }
      if fails >= FAIL_THRESHOLD || ![ :generic, :rate_limit ].include?(kind)
        level = [ provider.mute_level, MUTES.size - 1 ].min
        attrs.merge!(unavailable_until: now + MUTES[level], mute_level: [ level + 1, MUTES.size - 1 ].min)
        Rails.logger.warn("[Health] provider #{provider.slug} dimute #{MUTES[level].inspect} (#{kind}, #{fails}x): #{msg}")
      end
      provider.update_columns(attrs)
      source_fail!(provider, error, adapter: adapter, kind: kind)
    rescue StandardError => e
      Rails.logger.warn("[Health] fail! #{provider&.slug}: #{e.class} #{e.message}")
    end

    # Hanya menandai SUMBER (dipakai juga saat adapter utama gagal tetapi cadangan berhasil):
    # token/kuota → milik sumber kecuali provider punya key sendiri; host down → hanya untuk hub (host bersama).
    def source_fail!(provider, error, adapter: nil, kind: nil)
      kind ||= classify(error)
      source_wide = case kind
      when :quota, :auth, :rate_limit then provider.api_key.blank?
      when :down then hub_adapter?(provider, adapter)
      else false
      end
      src = source_for(provider, adapter)
      return unless src && source_wide && corroborated?(src, provider)
      mark_source!(src, kind, "#{error.class.name.demodulize}: #{error.message}".truncate(250))
    rescue StandardError => e
      Rails.logger.warn("[Health] source_fail! #{provider&.slug}: #{e.class} #{e.message}")
    end

    # Satu provider gagal belum cukup membuktikan sumbernya bermasalah (bisa platform upstream saja):
    # butuh beberapa provider berbeda dari sumber yang sama gagal dalam FAIL_WINDOW (provider ini ikut dihitung).
    def corroborated?(src, provider)
      scope = Provider.where(api_source_id: src.id)
      scope = scope.or(Provider.where(api_source_id: nil)) if src.is_default?
      total = scope.count
      failed = scope.where("last_error_at > ?", FAIL_WINDOW.ago).where.not(last_error: nil).pluck(:id) | [ provider.id ]
      failed.size >= [ SOURCE_MIN_PROVIDERS, total ].min
    end

    # :quota (kuota harian) | :rate_limit (sementara) | :auth | :down (host hub tidak bisa dihubungi) | :generic
    def classify(error)
      code = error.respond_to?(:code) ? error.code.to_i : 0
      m = error.message.to_s
      return :quota if m.match?(QUOTA_RE)
      return :rate_limit if code == 429 || m.match?(RATE_RE)
      return :auth if error.is_a?(MissingApiKey) || [ 401, 403 ].include?(code) || m.match?(AUTH_RE)
      return :down if [ 502, 503, 504, 520, 521, 522, 523, 524 ].include?(code) || m.match?(/timeout|koneksi|connection|tidak merespons/i)
      :generic
    end

    def mark_source!(src, kind, msg)
      until_at = case kind
      when :quota then next_utc_midnight
      when :auth  then Time.current + AUTH_MUTE
      when :rate_limit then Time.current + RATE_MUTE
      else Time.current + HUB_DOWN_MUTE
      end
      return if src.unhealthy_until.present? && src.unhealthy_until > until_at # sudah dimute lebih lama
      note = { quota: "Kuota habis", auth: "Token ditolak", rate_limit: "Rate limit", down: "Host tidak bisa dihubungi" }[kind] || "Gagal"
      src.update_columns(unhealthy_until: until_at, health_note: "#{note} — #{msg}".truncate(250), health_checked_at: Time.current)
      Rails.logger.warn("[Health] sumber #{src.slug} ditandai tidak sehat s/d #{until_at.utc.iso8601} (#{kind})")
    end

    def next_utc_midnight = Time.now.utc.beginning_of_day + 1.day

    def hub_adapter?(provider, adapter = nil)
      klass = adapter ? adapter.class.name : Adapters::REGISTRY[provider.adapter_slug]
      Adapters::HUBS.include?(klass)
    end

    def source_for(provider, adapter)
      return adapter.source if adapter.respond_to?(:source) && adapter.source
      provider.api_source || ApiSource.default
    end

    # Cek terjadwal semua sumber aktif: status hub + info token/kuota. Mengembalikan [[source, "ok ..."/"gagal ..."], ...]
    def check_sources!
      ApiSource.enabled.ordered.map do |src|
        client = Client.from_source(src)
        next [ src, "lewati: key kosong" ] unless client.configured?
        begin
          data = client.status
          key = data["key"] || {}
          n = Array(data["platforms"] || data["providers"] || data["data"]).size
          limit = (key["rate_limit_per_day"] || key["limit"]).to_i
          used  = (key["requests_today"] || key["used"]).to_i
          exp   = key["expires_at"].present? ? (Time.zone.parse(key["expires_at"].to_s) rescue nil) : nil
          attrs = { health_checked_at: Time.current, quota_limit: limit.nonzero?, quota_used: (limit.nonzero? ? used : nil), key_expires_at: exp }
          if limit.positive? && used >= limit
            attrs.merge!(unhealthy_until: next_utc_midnight, health_note: "Kuota habis (#{used}/#{limit})")
          elsif exp && exp < Time.current
            attrs.merge!(unhealthy_until: Time.current + AUTH_MUTE, health_note: "Token kedaluwarsa #{exp.to_date}")
          else
            attrs.merge!(unhealthy_until: nil, health_note: nil, last_tested_at: Time.current, last_test_result: "ok, #{n} entri#{" · kuota #{used}/#{limit}" if limit.positive?}")
          end
          src.update_columns(attrs)
          [ src, attrs[:health_note] || attrs[:last_test_result] ]
        rescue DracinApi::Error => e
          kind = classify(e)
          mark_source!(src, kind == :generic ? :down : kind, e.message)
          [ src, "gagal (#{kind}): #{e.message.truncate(120)}" ]
        end
      end
    end
  end
end
