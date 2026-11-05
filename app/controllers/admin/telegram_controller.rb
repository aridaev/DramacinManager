# Auto Poster Telegram per instance (/admin/instances/:id/telegram): login akun Telegram lewat QR (MTProto via sidecar),
# muat daftar grup/channel, lalu atur jadwal/konten tiap tujuan. Akses mengikuti Admin::AutoPostsController.
class Admin::TelegramController < ApplicationController
  layout "application"
  before_action :load_instance
  before_action :load_account, except: :show

  PERMIT = [ :enabled, :interval_minutes, :max_seconds, :episodes_per_title, :genres, :remix, :bgm, :fixed_text, :promo_enabled, :promo_interval_minutes ].freeze

  def show
    @account = TelegramAccount.for(@instance)
    @targets = @account.persisted? ? @account.targets.order(enabled: :desc, can_post: :desc, title: :asc, topic_id: :asc).to_a : []
    # Hierarki: satu grup forum = satu kelompok berisi topic-topicnya (General dulu); non-forum = kelompok berisi satu baris.
    @groups = @targets.group_by { |tg| [ tg.peer_kind, tg.peer_id ] }.values.map { |rows| rows.sort_by(&:topic_id) }
    @configured = TelegramClient.from_settings.configured?
  end

  def qr_start
    cancel_pending
    res = client.qr_start
    Rails.cache.write(login_key, res["login_id"], expires_in: 15.minutes)
    render json: { ok: true, svg: res["svg"] }
  rescue TelegramClient::Error => e
    render json: { ok: false, message: e.message }, status: :bad_gateway
  end

  def qr_status
    lid = Rails.cache.read(login_key)
    return render(json: { ok: true, state: "gone" }) if lid.blank?
    res = client.qr_status(lid)
    finish_login(res) if res["state"] == "ok"
    render json: res.slice("state", "svg", "message").merge(ok: true, account: (@account.label if res["state"] == "ok"))
  rescue TelegramClient::Error => e
    render json: { ok: false, message: e.message }, status: :bad_gateway
  end

  def qr_password
    lid = Rails.cache.read(login_key)
    return render(json: { ok: false, message: t("admin.telegram.qr_gone") }, status: :conflict) if lid.blank?
    res = client.qr_password(lid, params[:password].to_s)
    finish_login(res)
    render json: { ok: true, state: "ok", account: @account.label }
  rescue TelegramClient::Error => e
    render json: { ok: false, message: e.message }, status: :unprocessable_entity
  end

  def qr_cancel
    cancel_pending
    head :no_content
  end

  def logout
    if @account.session.present?
      begin
        client.logout(@account.session)
      rescue TelegramClient::Error => e
        Rails.logger.warn("[Telegram] logout instance=#{@instance.id}: #{e.message}")
      end
    end
    @account.targets.update_all(enabled: false, next_run_at: nil, promo_enabled: false, promo_next_run_at: nil, updated_at: Time.current)
    @account.update!(session: nil, tg_user_id: nil, username: nil, display_name: nil, phone: nil, logged_in_at: nil, auth_failed_at: nil, last_error: nil)
    redirect_to admin_instance_telegram_path(@instance), notice: t("admin.telegram.logged_out")
  end

  def sync_dialogs
    return redirect_to(admin_instance_telegram_path(@instance), alert: t("admin.telegram.need_login")) unless @account.logged_in?
    n = @account.sync_dialogs!
    redirect_to admin_instance_telegram_path(@instance), notice: t("admin.telegram.synced", n: n)
  rescue TelegramClient::AuthError => e
    @account.mark_auth_failed!(e.message)
    redirect_to admin_instance_telegram_path(@instance), alert: t("admin.telegram.auth_dead")
  rescue TelegramClient::Error => e
    redirect_to admin_instance_telegram_path(@instance), alert: e.message
  end

  # Simpan semua baris: params targets[<id>][field]; hanya baris yang berubah disentuh.
  def bulk_update
    rows = params.fetch(:targets, {}).permit!.to_h
    saved, errors = 0, []
    @account.targets.where(id: rows.keys).each do |target|
      target.assign_attributes(ActionController::Parameters.new(rows[target.id.to_s]).permit(PERMIT))
      next unless target.changed?
      target.save ? saved += 1 : errors << "#{target.display_title}: #{target.errors.full_messages.join(', ')}"
    end
    flash[:notice] = t("admin.telegram.bulk_saved", n: saved) if saved.positive? || errors.empty?
    flash[:alert] = errors.join(" · ") if errors.any?
    redirect_to admin_instance_telegram_path(@instance)
  end

  def run_now
    target = @account.targets.find(params[:target_id])
    back = admin_instance_telegram_path(@instance, anchor: "tg-#{target.id}")
    return redirect_to(back, alert: t("admin.telegram.need_login")) unless @account.logged_in?
    return redirect_to(back, alert: t("admin.telegram.cannot_post", title: target.display_title)) unless target.ready?
    target.update_columns(last_status: "antre…")
    TelegramPostJob.perform_later(target.id, manual: true)
    redirect_to back, notice: t("admin.telegram.run_now_queued")
  end

  def destroy_target
    target = @account.targets.find(params[:target_id])
    target.destroy
    redirect_to admin_instance_telegram_path(@instance), notice: t("admin.telegram.target_deleted", title: target.display_title)
  end

  # ---- Promosi: teks (+ gambar opsional) per tujuan, dirotasi sesuai jadwal promosi target ----
  def create_promo
    target = @account.targets.find(params[:target_id])
    back = promo_back(target)
    promo = target.promos.new(body: params[:body].to_s.strip)
    processed = nil
    if params[:image].present?
      promo.has_image = true
      processed = TelegramPromo.process_image(params[:image])
    end
    promo.transaction do
      promo.save!
      promo.write_image!(processed) if processed
    end
    redirect_to back, notice: t("admin.telegram.promo.created")
  rescue TelegramPromo::ImageError => e
    redirect_to back, alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to back, alert: e.record.errors.full_messages.to_sentence
  end

  def update_promo
    promo = find_promo
    attrs = {}
    attrs[:body] = params[:body].to_s.strip if params.key?(:body)
    attrs[:enabled] = ActiveModel::Type::Boolean.new.cast(params[:enabled]) if params.key?(:enabled)
    promo.update!(attrs)
    redirect_to promo_back(promo.telegram_target), notice: t("admin.telegram.promo.saved")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to promo_back(promo.telegram_target), alert: e.record.errors.full_messages.to_sentence
  end

  def destroy_promo
    promo = find_promo
    promo.destroy
    redirect_to promo_back(promo.telegram_target), notice: t("admin.telegram.promo.deleted")
  end

  def promo_image
    promo = find_promo
    return head(:not_found) unless promo.image_exists?
    send_file promo.image_path, type: "image/jpeg", disposition: "inline"
  end

  def promo_run_now
    target = @account.targets.find(params[:target_id])
    back = promo_back(target)
    return redirect_to(back, alert: t("admin.telegram.need_login")) unless @account.logged_in?
    return redirect_to(back, alert: t("admin.telegram.cannot_post", title: target.display_title)) unless target.ready?
    return redirect_to(back, alert: t("admin.telegram.promo.need_active", title: target.display_title)) unless target.promos.active.exists?
    target.update_columns(promo_last_status: "antre…")
    TelegramPromoJob.perform_later(target.id, manual: true)
    redirect_to back, notice: t("admin.telegram.promo.run_now_queued")
  end

  private
  def find_promo = TelegramPromo.joins(:telegram_target).where(telegram_targets: { telegram_account_id: @account.id }).find(params[:promo_id])
  def promo_back(target) = admin_instance_telegram_path(@instance, anchor: "tg-#{target.id}")

  def load_instance
    scope = admin? ? Instance.all : Instance.where(created_by_id: current_user.id)
    @instance = scope.find(params[:instance_id])
  end

  def load_account = @account = TelegramAccount.for(@instance)
  def client = @client ||= TelegramClient.from_settings
  def login_key = "tg_login:#{@instance.id}"

  def cancel_pending
    lid = Rails.cache.read(login_key)
    return if lid.blank?
    Rails.cache.delete(login_key)
    client.qr_cancel(lid)
  rescue TelegramClient::Error
    nil
  end

  def finish_login(res)
    @account.store_login!(session: res["session"], user: res["user"])
    Rails.cache.delete(login_key)
  end
end
