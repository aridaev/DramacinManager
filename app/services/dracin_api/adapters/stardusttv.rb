module DracinApi
  module Adapters
    # https://stardusttv2.goodbos.online — header x-token; bukan skema /api/*; lang format `id_ID`
    #   /video/hot-list?page=&page_size=&lang=      → [ { vid, name, cover, intro, episode_total, free_episodes, tag } ]
    #   /video/search?keyword=&page=&page_size=     → [...]
    #   /category/video?category_id=&page=          → [...]
    #   /video/summary-info?vid=                    → [ { vid, name, cover, episode_total } ]
    #   /video/episodes?vid=&lang=                  → { vid, name, cover, intro?, episode_total, episodes: [ { episode, name, duration_sec, is_free, m3u8 } ] }
    class Stardusttv < Base
      default_host "https://stardusttv2.goodbos.online"
      LANG_MAP = { "id" => "id_ID", "en" => "en_US", "ja" => "ja_JP", "ko" => "ko_KR", "es" => "es_ES", "zh" => "zh_CN", "th" => "th_TH", "pt" => "pt_BR", "fr" => "fr_FR", "de" => "de_DE", "ar" => "ar_SA", "vi" => "vi_VN" }.freeze

      def home
        p1, p2 = concurrently(-> { list(1) }, -> { list(2) })
        [ section(I18n.t("template.v1.sections.trending"), p1), section(I18n.t("template.v1.sections.for_you"), p2) ]
      end

      def search(q, page: 1)
        page(as_list(get("/video/search", keyword: q, page: page, page_size: 30, lang: lang)).map { |d| to_drama(d) }, page: page, has_more: false)
      end

      def detail(id)
        d = episodes_data(id)
        drama(id: d["vid"] || id, title: d["name"].to_s.strip, cover: d["cover"], synopsis: d["intro"], genres: Array(d["tag"]).first(5),
              episodes: d["episode_total"].to_i.nonzero?, language: nil, rating: nil, year: nil, status: nil)
      end

      def episodes(id)
        Array(episodes_data(id)["episodes"]).map do |e|
          episode(number: e["episode"], title: "EP #{e['episode']}", thumbnail: nil, duration: seconds_to_clock(e["duration_sec"]),
                  locked: e["m3u8"].blank?, payload: e.slice("m3u8"))
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        url = item.payload["m3u8"]
        return nil if url.blank?
        stream(url: url, episode: ep)
      end

      private
      def as_list(j) = j.is_a?(Array) ? j : Array(j["data"] || j["list"] || j["rows"])
      def list(page) = as_list(get("/video/hot-list", page: page, page_size: 30, lang: lang)).map { |d| to_drama(d) }
      def episodes_data(id) = get("/video/episodes", vid: id, lang: lang)

      def to_drama(d)
        tags = d["tag"].is_a?(String) ? d["tag"].split(/[,，]/) : Array(d["tag"]).map { |t| t.is_a?(Hash) ? t["name"] : t }
        drama(id: d["vid"], title: d["name"].to_s.strip, cover: d["cover"], synopsis: d["intro"], genres: tags.first(5),
              episodes: d["episode_total"].to_i.nonzero?, language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
