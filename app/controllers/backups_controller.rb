class BackupsController < ApplicationController
  def show
    send_data JSON.pretty_generate(BackupService.export), filename: "fluxo-de-caixa-#{Date.current.iso8601}.json", type: 'application/json', disposition: 'attachment'
  end
  def create
    upload = params[:file]
    raise BackupService::InvalidBackup, 'Selecione um arquivo .json.' unless upload.respond_to?(:tempfile) && File.extname(upload.original_filename).downcase == '.json'
    raise BackupService::InvalidBackup, 'Backup excede 10 MB.' if upload.size > 10.megabytes
    data = BackupService.parse(upload.read)
    Preview.purge_expired!
    current_user.previews.where(purpose: 'backup').destroy_all
    @preview = current_user.previews.create!(purpose: 'backup', payload: { 'backup' => data, 'fingerprint' => BackupService.fingerprint }, expires_at: 30.minutes.from_now)
    session[:backup_preview_id] = @preview.id
    @data = data
    render :preview
  rescue BackupService::InvalidBackup => e
    redirect_to settings_path, alert: e.message
  ensure
    upload&.tempfile&.close! if upload.respond_to?(:tempfile)
  end
  def restore
    preview = current_user.previews.where(purpose: 'backup').where('expires_at > ?', Time.current).find(session[:backup_preview_id])
    raise BackupService::InvalidBackup, 'Confirme a substituição dos dados.' unless params[:confirm] == '1'
    GoogleCalendarEntrySync.suppress_callbacks do
      Preview.transaction do
        preview.lock!
        data = preview.payload
        raise BackupService::InvalidBackup, 'Os dados mudaram. Gere uma nova prévia.' unless data['fingerprint'] == BackupService.fingerprint
        BackupService.restore!(data.fetch('backup'))
        preview.destroy!
      end
    end
    sync_google_calendar_if_connected
    session.delete(:backup_preview_id)
    redirect_to settings_path, notice: 'Backup restaurado com sucesso.'
  rescue BackupService::InvalidBackup, ActiveRecord::ActiveRecordError, ArgumentError => e
    redirect_to settings_path, alert: "Restauração não realizada: #{e.message}"
  end
  def cancel
    current_user.previews.where(purpose: 'backup').destroy_all
    session.delete(:backup_preview_id)
    redirect_to settings_path, notice: 'Restauração cancelada; dados preservados.', status: :see_other
  end
end
