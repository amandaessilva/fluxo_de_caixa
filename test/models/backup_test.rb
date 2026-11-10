require 'test_helper'
class BackupTest < ActiveSupport::TestCase
  setup { setup_finances; entry }
  test 'backup preserva dados e vínculos sem exportar credenciais' do
    rule = RecurringRule.create!(category: @category, description: 'Fixa', amount: 30, day: 5, starts_on: '2027-01-01', kind: 'expense')
    YearBuilder.call(2027)
    payload = BackupService.export
    assert_not payload.to_json.include?('password')
    entry(description: 'Remover')
    BackupService.restore!(payload)
    assert_equal 13, Entry.count
    assert_equal @year.id, FinancialYear.find_by!(year: 2027).previous_year_id
    assert_equal rule.id, Entry.order(:date).last.recurring_rule_id
  end
  test 'backup inválido faz rollback após exclusão' do
    payload = BackupService.export
    payload['data']['entries'].last['amount'] = '-1'
    assert_raises(ActiveRecord::RecordInvalid) { BackupService.restore!(payload) }
    assert_equal 1, Entry.count
    assert_equal BigDecimal('10'), Entry.first.amount
  end
  test 'backup rejeita estrutura indevida' do
    assert_raises(BackupService::InvalidBackup) { BackupService.parse('{bad') }
    assert_raises(BackupService::InvalidBackup) { BackupService.parse('{"version":2,"data":{}}') }
  end
  test 'prévia é criptografada e expira' do
    user = User.create!(email: 'teste@example.com', password: 'senha-sintetica-segura')
    preview = user.previews.create!(purpose: 'backup', payload: { 'secret' => 'financeiro' }, expires_at: 1.minute.ago)
    assert_not_includes preview.encrypted_payload, 'financeiro'
    assert_equal 'financeiro', preview.payload['secret']
    Preview.purge_expired!
    assert_not Preview.exists?(preview.id)
  end
end
