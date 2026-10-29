# Pengaturan auto posting per instance (platform: instagram). Form terpisah dari form utama instance
# (lihat admin/instances/_auto_post.html.erb). Logika kirim postingan belum ada — hanya simpan konfigurasi.
class Admin::AutoPostsController < ApplicationController
  before_action :load_instance
  before_action :load_auto_post, only: [ :update ]

  def update
    @auto_post.assign_attributes(params.require(:auto_post).permit(:enabled, :provider_slug, :drama_id, :drama_title, :interval_minutes))
    @auto_post.cookies = params.dig(:auto_post, :cookies).to_unsafe_h if params.dig(:auto_post, :cookies).present?
    if @auto_post.save
      redirect_to edit_admin_instance_path(@instance, anchor: "sec-autopost"), notice: t("admin.auto_post.saved", platform: @auto_post.platform.titleize)
    else
      redirect_to edit_admin_instance_path(@instance, anchor: "sec-autopost"), alert: @auto_post.errors.full_messages.join(", ")
    end
  end

  # Daftar judul untuk dropdown: beranda provider (+ hasil pencarian bila q diisi). JSON [{ id, title }].
  def dramas
    provider = Provider.enabled.supported.find_by(slug: params[:provider]) or return render(json: { items: [], error: t("admin.auto_post.provider_unknown") }, status: :unprocessable_entity)
    catalog = DracinApi::Catalog.for(provider)
    items = catalog.home.flat_map(&:items)
    items = catalog.search(params[:q].to_s.strip, page: 1).items + items if params[:q].to_s.strip.length >= 2
    render json: { items: items.uniq(&:id).first(300).map { |d| { id: d.id.to_s, title: d.title.to_s } } }
  rescue DracinApi::Error => e
    render json: { items: [], error: e.message }, status: :bad_gateway
  end

  private
  def load_instance
    scope = admin? ? Instance.all : Instance.where(created_by_id: current_user.id)
    @instance = scope.find(params[:instance_id])
  end

  def load_auto_post
    platform = AutoPost::PLATFORMS.include?(params[:platform]) ? params[:platform] : AutoPost::PLATFORMS.first
    @auto_post = @instance.auto_posts.find_or_initialize_by(platform: platform)
  end
end
