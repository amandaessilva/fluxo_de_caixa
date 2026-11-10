class BackupService
  class InvalidBackup < StandardError; end
  MODELS = { 'categories' => Category, 'financial_years' => FinancialYear,
    'recurring_rules' => RecurringRule, 'monthly_limits' => MonthlyLimit, 'entries' => Entry }.freeze
  def self.export
    { 'version' => 1, 'exported_at' => Time.current.iso8601,
      'data' => MODELS.transform_values { |model| model.order(:id).map { |r| r.attributes.except('created_at', 'updated_at') } } }
  end

  def self.parse(text)
    raise InvalidBackup, 'Backup excede 10 MB.' if text.bytesize > 10.megabytes
    payload = JSON.parse(text)
    raise InvalidBackup, 'Versão ou estrutura de backup inválida.' unless payload['version'] == 1 && payload['data'].is_a?(Hash) && payload['data'].keys.sort == MODELS.keys.sort
    MODELS.each do |key, model|
      rows = payload['data'][key]
      raise InvalidBackup, "Tabela inválida: #{key}." unless rows.is_a?(Array) && rows.size <= 100_000
      rows.each do |attrs|
        raise InvalidBackup, "Campos inválidos: #{key}." unless attrs.is_a?(Hash) && (attrs.keys - model.column_names).empty? && attrs['id'].is_a?(Integer) && attrs['id'].positive?
      end
      raise InvalidBackup, "IDs repetidos em #{key}." if rows.map { |r| r['id'] }.uniq.size != rows.size
    end
    payload
  rescue JSON::ParserError
    raise InvalidBackup, 'JSON inválido.'
  end

  def self.fingerprint = Digest::SHA256.hexdigest(export.fetch('data').to_json)

  def self.restore!(payload)
    payload = parse(payload.to_json)
    ApplicationRecord.transaction do
      Entry.delete_all
      MonthlyLimit.delete_all
      RecurringRule.delete_all
      FinancialYear.update_all(previous_year_id: nil)
      FinancialYear.delete_all
      Category.delete_all
      MODELS.each do |key, model|
        rows = payload.fetch('data').fetch(key)
        rows = rows.sort_by { |r| r.fetch('year') } if key == 'financial_years'
        rows.each { |attrs| model.create!(attrs) }
      end
      raise InvalidBackup, 'Conferência do backup falhou.' unless MODELS.all? { |key, model| model.count == payload['data'][key].size }
    end
  end
end
