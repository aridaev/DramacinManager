module DracinApi
  module Adapters
    # https://cubetv.goodbos.online — auth ?code=KEY
    #   /api/home?lang=                → { banner, rows: [ { moduleName, videos: [ { videoid, videoName, cover, summary, totalEpisodeNum, tagInfo } ] } ] }
    #   /api/search?q=&lang=           → { rows: [...] }
    #   /api/detail/:videoid?lang=     → { data: { videoName, cover, summary, latestEpisodeNumber, tagInfo, ... } }
    #   /api/episodes/:videoid?lang=   → { rows: [ { episodeNumber, episodeid, duration, lockStatus, subtitles: [ { lang, url } ], playUrl?/videoUrl?/m3u8? } ] }
    class Cubetv < Base
      default_host "https://cubetv.goodbos.online"
      VIDEO_KEYS = %w[videoUrls playUrl videoUrl m3u8 m3u8Url hlsUrl url mp4Url playAddress].freeze

      def home
        Array(get("/api/home", lang: lang)["rows"]).filter_map do |row|
          items = Array(row["videos"]).map { |v| to_drama(v) }
          section(row["moduleName"].to_s.strip.presence || I18n.t("template.v1.sections.featured"), items) if items.any?
        end
      end

      def search(q, page: 1)
        page(Array(get("/api/search", q: q, lang: lang)["rows"]).map { |v| to_drama(v) }, page: 1, has_more: false)
      end

      def detail(id)
        d = get("/api/detail/#{id}", lang: lang)["data"] || {}
        to_drama(d.merge("videoid" => d["videoid"] || id, "totalEpisodeNum" => d["totalEpisodeNum"] || d["latestEpisodeNumber"]))
      end

      def episodes(id)
        Array(get("/api/episodes/#{id}", lang: lang)["rows"]).map do |e|
          episode(number: e["episodeNumber"], title: "EP #{e['episodeNumber']}", thumbnail: e["cover"], duration: seconds_to_clock(e["duration"]),
                  locked: video_of(e).blank?, payload: e.slice("subtitles", *VIDEO_KEYS))
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        url = video_of(item.payload)
        return nil if url.blank?
        subs = Array(item.payload["subtitles"]).filter_map { |s| s["url"].present? ? subtitle(lang: s["lang"], url: s["url"]) : nil }
        stream(url: url, episode: ep, sources: video_sources(item.payload), subtitles: subs)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      # videoUrls bisa berupa [ { quality|resolution|name, url } ], { "720p" => url }, atau string.
      def video_sources(e)
        v = e["videoUrls"]
        list = case v
               when Array then v.filter_map { |x| x.is_a?(Hash) ? { label: (x["quality"] || x["resolution"] || x["name"] || x["label"]).to_s, url: x["url"] || x["playUrl"] || x["src"] } : (x.is_a?(String) ? { label: "Auto", url: x } : nil) }
               when Hash  then v.map { |k, u| { label: k.to_s, url: u } }
               when String then [ { label: "Auto", url: v } ]
               else []
               end
        list = list.select { |x| x[:url].present? }
        list = [ { label: "Auto", url: VIDEO_KEYS.drop(1).map { |k| e[k] }.find(&:present?) } ] if list.empty? && VIDEO_KEYS.drop(1).any? { |k| e[k].present? }
        list.map { |x| x.merge(label: x[:label].to_s.downcase.sub(/\A(\d{3,4})\z/, '\\1p')) }.sort_by { |x| -x[:label].to_i }
      end

      def video_of(e) = video_sources(e).then { |l| (l.find { |x| x[:label].to_i == 720 } || l.first)&.dig(:url) }

      def to_drama(d)
        tags = Array(d["tagInfo"]).map { |t| t.is_a?(Hash) ? (t["tagName"] || t["name"]) : t }
        drama(id: d["videoid"], title: (d["videoName"] || d["videoAliasName"]).to_s.strip, cover: d["cover"], synopsis: d["summary"],
              genres: tags.first(5), episodes: d["totalEpisodeNum"].to_i.nonzero?, language: nil, rating: nil, year: d["releaseDate"].to_s[0, 4].presence&.to_i, status: nil)
      end
    end
  end
end
