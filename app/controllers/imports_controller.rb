class ImportsController < ApplicationController
  before_action :purge
  def new; end
  def create
    upload = params[:file]
    raise XlsxImporter::InvalidFile, 'Selecione um arquivo XLSX.' unless upload.respond_to?(:tempfile)
    data = XlsxImporter.new(upload.tempfile.path, filename: upload.original_filename, fallback_year: params[:year], force_year: params[:force_year] == '1').preview
    current_user.previews.where(purpose: 'xlsx').destroy_all
    @preview = current_user.previews.create!(purpose: 'xlsx', payload: data, expires_at: 30.minutes.from_now)
    session[:import_preview_id] = @preview.id
    redirect_to import_path
  rescue XlsxImporter::InvalidFile, ArgumentError => e
    redirect_to new_import_path, alert: e.message
  ensure
    upload&.tempfile&.close! if upload.respond_to?(:tempfile)
  end
  def show
    @preview = find_preview
    @data = @preview.payload
  end
  def commit
    preview = find_preview
    raise XlsxImporter::InvalidFile, 'Confirme a revisão dos avisos.' unless params[:reviewed] == '1'
    Preview.transaction do
      preview.lock!
      @year = XlsxImporter.commit!(preview.payload, replace: params[:replace] == '1')
      preview.destroy!
    end
    session.delete(:import_preview_id)
    redirect_to root_path(year: @year.year), notice: 'Importação concluída. Quantidades e totais conferidos com a prévia.'
  rescue XlsxImporter::InvalidFile, ActiveRecord::RecordInvalid => e
    redirect_to import_path, alert: e.message
  end
  def destroy
    current_user.previews.where(purpose: 'xlsx').destroy_all
    session.delete(:import_preview_id)
    redirect_to settings_path, notice: 'Importação cancelada. Seus registros foram preservados.', status: :see_other
  end
  private
  def purge = Preview.purge_expired!
  def find_preview
    current_user.previews.where(purpose: 'xlsx').where('expires_at > ?', Time.current).find(session[:import_preview_id])
  end
end
