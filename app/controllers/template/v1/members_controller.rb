# Akun penonton (bebas iklan) di situs publik instance. Terpisah total dari login dashboard (Devise User).
class Template::V1::MembersController < Template::V1::BaseController
  before_action :require_members!
  before_action :require_member!, only: [ :deposit, :logout ]

  def tt(key, **opts) = t("template.#{tpl}.#{key}", **opts, default: :"template.v1.#{key}")

  def show
    @member = current_member
    @request = @member&.pending_request
    @history = @member ? @member.deposit_requests.ordered.limit(10) : []
  end

  def login
    m = current_instance.members.find_by(username: params[:username].to_s.strip.downcase)
    if m&.authenticate(params[:password].to_s)
      sign_in_member(m)
      redirect_to template_v1_member_path, notice: tt("members.welcome", name: m.username)
    else
      redirect_to template_v1_member_path, alert: tt("members.bad_login")
    end
  end

  def register
    m = current_instance.members.new(username: params[:username], password: params[:password], password_confirmation: params[:password_confirmation].presence || params[:password])
    if m.save
      sign_in_member(m)
      redirect_to template_v1_member_path, notice: tt("members.registered", name: m.username)
    else
      redirect_to template_v1_member_path(tab: "register"), alert: m.errors.full_messages.join(", ")
    end
  end

  def logout
    session.delete(member_session_key)
    redirect_to template_v1_root_path, notice: tt("members.logged_out")
  end

  def deposit
    req = current_member.deposit_requests.new(instance: current_instance, days: current_instance.adfree_days, amount: current_instance.adfree_price, note: params[:note].to_s.strip.first(200))
    req.attach_proof(params[:proof])
    if req.errors.empty? && req.save
      redirect_to template_v1_member_path, notice: tt("members.deposit_sent")
    else
      req.delete_proof_file if req.proof_path.present?
      redirect_to template_v1_member_path, alert: req.errors.full_messages.join(", ")
    end
  end

  private
  def require_members!
    head :not_found unless current_instance&.members_enabled?
  end

  def require_member!
    redirect_to template_v1_member_path, alert: tt("members.login_first") unless current_member
  end

  def sign_in_member(m)
    session[member_session_key] = m.id
    m.update_columns(last_login_at: Time.current)
  end
end
