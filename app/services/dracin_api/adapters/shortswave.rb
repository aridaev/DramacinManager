module DracinApi
  module Adapters
    # https://shortwave.goodbos.online — auth ?code=KEY, lang `id`→`in`
    #   /api/home?page=&lang=                   → { data: [ { drama_id, title, cover, chapters, tags, sub_tags } ], has_next }
    #   /api/all?page=&size=&lang=              → { data: [ { drama_id, title, cover, chapters, description, charge_chapters } ], has_next }
    #   /api/search?q=&lang=                    → { data: [...] }
    #   /api/drama/:dramaId/episodes?lang=      → { data: [ { chapter_id, chapter_index, chapter_name, first_frame, is_free } ] }
    #   /api/stream/:dramaId/:chapterId/v.m3u8?code=&lang=  → playlist HLS (server mereka yang unlock)
    class Shortswave < Base
      default_host "https://shortwave.goodbos.online"
      LANG_MAP = { "id" => "in" }.freeze

      def home
        home, all = concurrently(-> { get("/api/home", page: 1, lang: lang) }, -> { get("/api/all", page: 1, size: 48, lang: lang) })
        [
          section(I18n.t("template.v1.sections.trending"), Array(home["data"]).map { |d| to_drama(d) }),
          section(I18n.t("template.v1.sections.latest"), Array(all["data"]).map { |d| to_drama(d) })
        ]
      end

      def search(q, page: 1)
        page(Array(get("/api/search", q: q, lang: lang)["data"]).map { |d| to_drama(d) }, page: 1, has_more: false)
      end

      def detail(id)
        d = Array(get("/api/all", page: 1, size: 48, lang: lang)["data"]).find { |x| x["drama_id"].to_s == id.to_s } ||
            Array(get("/api/home", page: 1, lang: lang)["data"]).find { |x| x["drama_id"].to_s == id.to_s }
        return to_drama(d) if d
        eps = episodes(id)
        drama(id: id, title: "##{id}", cover: eps.first&.thumbnail, episodes: eps.size.nonzero?, language: nil, rating: nil, year: nil, status: nil, synopsis: nil)
      end

      def episodes(id)
        Array(get("/api/drama/#{id}/episodes", lang: lang)["data"]).map do |c|
          episode(number: c["chapter_index"], title: c["chapter_name"].presence || "EP #{c['chapter_index']}", thumbnail: c["first_frame"],
                  duration: nil, locked: false, payload: c.slice("chapter_id"))
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        require_key!
        url = "#{host}/api/stream/#{id}/#{item.payload['chapter_id']}/v.m3u8?#{URI.encode_www_form(code: api_key, lang: lang)}"
        stream(url: url, episode: ep)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def to_drama(d)
        drama(id: d["drama_id"], title: d["title"].to_s.strip, cover: d["cover"], synopsis: d["description"],
              genres: Array(d["tags"].presence || d["sub_tags"]).first(5), episodes: d["chapters"].to_i.nonzero?,
              language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
