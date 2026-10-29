module DracinApi
  module Adapters
    # https://flickreels.goodbos.online — auth x-token / ?code=; lang `id`→`in`; search di DracinAPI mengembalikan null (tidak ada)
    #   /api/home?lang=&page=      → { data: { data: [ { playlet_id, title, cover, upload_num, introduce, tag_list } ], page_info: { total } } }
    #   /api/list?lang=&page=      → sama
    #   /batchload/:id?lang=       → { data: { title, cover, introduce, upload_num, playlet_detail, list: [ { chapter_num, chapter_title, chapter_cover, duration, hls_url (±40 menit), is_lock } ] } }
    class Flickreels < Base
      default_host "https://flickreels.goodbos.online"
      LANG_MAP = { "id" => "in" }.freeze

      def home
        p1, p2 = concurrently(-> { list("/api/home", 1) }, -> { list("/api/list", 2) })
        [ section(I18n.t("template.v1.sections.for_you"), p1), section(I18n.t("template.v1.sections.latest"), p2) ]
      end

      # Tidak ada pencarian di API; saring dari halaman home.
      def search(q, page: 1)
        needle = q.to_s.downcase
        items = (list("/api/home", 1) + list("/api/list", 2) + list("/api/list", 3)).uniq(&:id).select { |d| d.title.to_s.downcase.include?(needle) }
        page(items, page: 1, has_more: false)
      end

      def detail(id)
        d = batch(id)
        tags = Array(d.dig("playlet_detail", "tag_list") || d["tag_list"]).map { |t| t.is_a?(Hash) ? (t["tag_name"] || t["name"]) : t }
        drama(id: id, title: d["title"].to_s.strip, cover: d["cover"], synopsis: d["introduce"], genres: tags.first(5),
              episodes: (d["upload_num"] || Array(d["list"]).size).to_i.nonzero?, language: nil, rating: nil, year: nil, status: nil)
      end

      def episodes(id)
        Array(batch(id)["list"]).map do |c|
          episode(number: c["chapter_num"], title: "EP #{c['chapter_num']}", thumbnail: c["chapter_cover"], duration: seconds_to_clock(c["duration"]),
                  locked: c["hls_url"].blank?, payload: c.slice("hls_url", "chapter_id"))
        end
      end

      def play(id, ep)
        item = find_episode(id, ep) or return nil
        url = item.payload["hls_url"]
        return nil if url.blank?
        stream(url: url, episode: ep, proxied: true)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key), headers: { "x-token" => api_key }) }
      end

      def batch(id) = get("/batchload/#{id}", lang: lang)["data"] || {}

      def list(path, page)
        Array(get(path, lang: lang, page: page).dig("data", "data")).map do |d|
          tags = Array(d["tag_list"]).map { |t| t.is_a?(Hash) ? (t["tag_name"] || t["name"]) : t }
          drama(id: d["playlet_id"], title: d["title"].to_s.strip, cover: d["cover"], synopsis: d["introduce"], genres: tags.first(5),
                episodes: d["upload_num"].to_i.nonzero?, language: nil, rating: nil, year: nil, status: nil)
        end
      end
    end
  end
end
