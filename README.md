# Fluxo de Caixa

Aplicação pessoal em português do Brasil, com Ruby 3.4.8, Rails 8.1.4.1, SQLite, ERB, Turbo, Stimulus e Roo. Não usa React, Vite ou serviços externos para armazenar dados financeiros.

## Começar

Você precisa de **Ruby 3.3 ou superior** (versão testada: 3.4.8), Bundler e das ferramentas de compilação das gems. Em Ubuntu/Debian, essas ferramentas normalmente são `build-essential`, `libyaml-dev`, `libssl-dev`, `zlib1g-dev` e `libsqlite3-dev`. Instale Ruby com seu gerenciador de versões, por exemplo rbenv ou mise. Este projeto não modifica o Ruby do sistema.

No terminal, dentro do projeto:

```bash
cd /home/pandin/Documentos/workdir/fluxo_de_caixa
ruby -v
gem install bundler
bundle install
bin/rails db:migrate
bin/rails account:setup
bin/rails server -b localhost
```

Abra **http://localhost:3000**. Use `localhost` também no `GOOGLE_REDIRECT_URI` para que a sessão OAuth retorne ao mesmo host. A tarefa `account:setup` pede e-mail, senha de pelo menos 12 caracteres e confirmação, sem mostrar a senha no terminal. Não há usuário ou senha padrão. É uma aplicação para uma pessoa: executar essa tarefa novamente atualiza a conta existente. Não é um sistema multiusuário com carteiras isoladas.

A primeira visita autenticada leva às Configurações. Crie um ano financeiro e informe seu saldo inicial; depois crie categorias e limites. Não há valores pessoais ou dados de demonstração nos seeds. Para preparar o banco automaticamente também pode usar `bin/rails db:prepare`.

**Neste ambiente de entrega:** Ruby não estava instalado. Para validar o código foi usado um runtime temporário em `/tmp/fluxo-runtime`. Enquanto esse diretório existir, `source /tmp/fluxo-runtime/env` habilita Ruby no terminal atual. Essa instalação temporária não substitui a instalação normal acima e pode desaparecer ao reiniciar.

## O que está pronto

- Visão mensal com saldo inicial/final, entradas, benefícios recebidos/usados, despesas e variação.
- Alternância entre planejado e realizado, sem somar as situações.
- Cadastro, consulta, edição, exclusão, busca e filtros dos lançamentos; listas paginadas em 50 registros.
- Categorias globais com limites independentes em cada mês de cada ano.
- Resumo anual dos 12 meses e totais anuais para cada situação.
- Contas fixas com início, término opcional e dia de vencimento.
- Compras parceladas, centavos distribuídos exatamente e criação automática de anos futuros.
- Lembretes para despesas planejadas em dinheiro, sincronizados em um calendário dedicado do Google Calendar.
- Importação XLSX com prévia criptografada, avisos e confirmação de substituição.
- Backup JSON completo e restauração transacional com confirmação.
- Autenticação obrigatória, CSRF, sessão com validade de 12 horas e restrição de tentativas de login.
- Interface responsiva com navegação por teclado, labels e mensagens acessíveis.

## Planejado, realizado e saldos

O saldo é sempre calculado assim:

```text
saldo final = saldo inicial
            + entradas em dinheiro
            + benefícios recebidos
            − benefícios utilizados
            − saídas em dinheiro
```

O saldo inicial de fevereiro é o final de janeiro **da mesma situação**. O total anual mostra o início de janeiro e o fechamento de dezembro: não soma saldos mensais.

Planejado e realizado são cenários separados. Ao mudar um lançamento de planejado para realizado, ele sai do cenário planejado. Para preservar também a previsão original, mantenha um lançamento planejado e registre outro realizado. A importação preserva as duas tabelas separadamente.

Limites contabilizam **despesas + benefícios utilizados** da categoria, mês e situação selecionados. Limite vazio significa sem limite cadastrado; zero significa orçamento zero. Valores financeiros usam campos `decimal(15,2)` e `BigDecimal`. Como SQLite não possui DECIMAL nativo, os relatórios somam os atributos decimais no Ruby, evitando o `SUM` de ponto flutuante do SQLite. Frações de centavo são rejeitadas. O limite máximo de cada valor é inferior a 10 trilhões de reais.

## Continuar nos próximos anos

Em Configurações, crie 2027 depois de 2026:

1. Os limites são copiados mês a mês do ano anterior disponível, preservando diferenças entre janeiro, fevereiro etc.
2. O saldo inicial fica vinculado ao fechamento anterior, separadamente para planejado e realizado. Correções no ano anterior refletem no seguinte.
3. Somente as **regras de contas fixas cadastradas** geram novos lançamentos planejados. Despesas eventuais, salários e movimentações importadas não são adivinhados como recorrentes.
4. Informar um saldo inicial ao criar o ano torna-o independente. Também é possível desvinculá-lo nas Configurações.

Para água/luz com valor variável, cadastre uma estimativa e ajuste o lançamento de cada mês. O dia 31 é ajustado para o último dia dos meses mais curtos. Início e término são inclusivos. Cadastrar uma regra gera previsões em todos os anos existentes dentro da vigência; criar outro ano aplica as mesmas regras. A chave de origem impede gerar a mesma previsão duas vezes.

Remover uma regra não apaga os lançamentos já gerados. Para mudar o valor de uma previsão, edite o lançamento. Para alterar uma regra permanente, remova a antiga e cadastre outra com vigência futura, verificando os lançamentos já criados para evitar duplicidade.

### Lembretes no Google Calendar

Em Configurações, conecte o Google Calendar para criar o calendário separado **Pagamentos**. O app sincroniza despesas em dinheiro ainda planejadas, inclusive parcelas, contas fixas já geradas e previsões vencidas. Entradas e benefícios ficam de fora. A tarefa aparece como evento de dia inteiro na data de vencimento e se repete nos dias seguintes enquanto estiver planejada. Ao marcar a despesa como realizada, os avisos param e o calendário guarda um evento “Pago”.

O app cria avisos às 13h e às 19h, começando três dias antes do vencimento e repetindo diariamente até o registro como realizado. Esses avisos são eventos curtos no calendário para que o Google Calendar envie notificações nos horários definidos pelo app. A fatura de cartão que hoje é cadastrada em um único lançamento continua funcionando como uma despesa comum. O cadastro individual de compras, cartões e ciclos de fechamento e vencimento fica para uma etapa futura.

Para habilitar a conexão, ative a **Google Calendar API** em um projeto Google Cloud e crie um cliente OAuth do tipo aplicativo Web. Cadastre como URI de redirecionamento autorizado o endereço completo `http://localhost:3000/configuracoes/google-calendar/callback` no desenvolvimento local, ou `https://SEU_HOST/configuracoes/google-calendar/callback` em produção. O valor precisa ser idêntico em `GOOGLE_REDIRECT_URI` e na lista de URIs autorizados do cliente OAuth.

```text
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GOOGLE_REDIRECT_URI=http://localhost:3000/configuracoes/google-calendar/callback
```

Defina essas variáveis no mesmo ambiente e antes de iniciar o Rails. Se usar valores exportados no terminal, reinicie o servidor nesse terminal após configurá-los. Este projeto não carrega automaticamente valores de um arquivo `.env`.

Os tokens OAuth ficam criptografados no banco e não entram no backup JSON. A autorização usa o escopo do Google para calendários secundários criados pelo app. Os eventos pertencem à sua conta e podem ser editados manualmente no Google Calendar; o app continua sendo a fonte principal e não importa edições feitas no calendário. Desconectar remove os eventos criados pelo app e revoga a autorização; o calendário vazio “Pagamentos” permanece na sua lista do Google Calendar e será reutilizado se você reconectar.

### Parcelas entre 2026 e 2027

No novo lançamento, informe o **valor total da compra**, a **data da primeira parcela** e o número de parcelas (2 a 120). Uma compra iniciada em novembro de 2026 com 10 parcelas gera novembro/dezembro em 2026 e janeiro/agosto em 2027. Se 2027 não existir, ele é criado com os limites e contas fixas.

Todas as parcelas nascem **planejadas**, mesmo que o formulário esteja em realizado. Marque cada parcela como realizada ao pagá-la. O total é dividido em centavos inteiros; o resto vai para as primeiras parcelas. O dia base é preservado: 31/jan → 28/fev → 31/mar. Editar ou excluir uma parcela afeta somente aquela parcela. Não há juros calculados automaticamente, edição em lote da série ou conciliação automática entre previsão e pagamento.

## Importar XLSX

**Validado com a planilha de referência:** foram reconhecidas as 12 abas mensais, os cabeçalhos “ent vale”/“said vale” e a tabela de previstos sem repetição dos títulos H/I. A conferência independente do XML com a prévia e com os registros em banco em memória confirmou quantidades, totais, saldos e limites. Nenhum valor financeiro pessoal foi incluído no código, nos testes ou nos seeds.

**Para reaproveitar a referência em 2027:** informe `2027` e marque **“Usar este ano mesmo que as datas da planilha pertençam a outro ano”**. Essa escolha, confirmada pelo usuário, ajusta apenas o ano das datas e fica registrada na prévia. Sem marcar a opção, as datas preenchidas na referência indicam 2026. A aplicação não usa o nome do arquivo para substituir o ano silenciosamente.

Na aplicação, abra Configurações → Importar XLSX. Confira o ano, envie o arquivo, revise a prévia e confirme. Cancelar não altera lançamentos, categorias ou limites. Um erro desfaz toda a gravação. Após salvar, o sistema compara contagens e totais por mês/situação/tipo e a quantidade de limites com a prévia.

Layout suportado:

| Região | Tratamento |
| --- | --- |
| Abas Janeiro…Dezembro (ou Jan…Dez, sem distinguir acentos/caixa) | Mês de referência |
| Linhas 6–126 | Realizado |
| Linhas 132–211 | Planejado |
| A | Data; se vazia, dia 15 do mês da aba |
| B | Descrição |
| C | Tipo/pagamento preservado como forma de pagamento |
| D | Grupo/categoria; vazio vira “Sem grupo”, com aviso |
| E | Observações |
| F | Juros preservados nas observações, sem novo lançamento |
| G | Entrada em dinheiro |
| H | Benefício recebido |
| I | Benefício utilizado |
| J | Saída em dinheiro |
| K | Referência apenas; não é importada |
| M/N, linhas 5–43 | Grupos e limites por mês |

Cada coluna financeira não zero gera seu próprio lançamento, inclusive quando uma linha contém vários valores. Algumas fórmulas da coluna K da referência consideram apenas dinheiro. A aplicação segue a regra solicitada, incluindo benefícios e mantendo situações separadas, por isso K não é usado como critério de igualdade. O saldo inicial deve ser revisado em Configurações: não é inferido da coluna K. Ao substituir um ano, o saldo inicial e seu vínculo são preservados.

O ano é identificado nos cabeçalhos (linhas 1–4) nas células de data e em campos “Ano” no início das abas auxiliares; se houver anos conflitantes, o arquivo é rejeitado, exceto quando o usuário escolhe explicitamente reaproveitar o calendário no ano informado. Sem ano identificável, usa-se o ano informado com aviso. O dia vem da data e o mês vem da aba. Datas inválidas, valores negativos, frações de centavo, limites duplicados e valores não interpretados bloqueiam a confirmação. Fórmulas nas colunas financeiras só são aproveitadas com resultado calculado em cache; abra e salve a planilha no Excel/LibreOffice se faltar esse resultado.

As abas auxiliares são inspecionadas: a prévia informa linhas com dados, quantidade de fórmulas e uma amostra de até 30 linhas. Possíveis lançamentos avulsos no formato A:K são destacados integralmente em uma seção separada, inclusive depois dessa amostra. **Elas não são importadas automaticamente.** Isso evita transformar resumos anuais ou tabelas de parcelas em despesas duplicadas. Revise os avisos e cadastre os dados relevantes manualmente; na referência, `Plan1` é uma estrutura vazia de receitas, despesas, contas fixas e parcelas, enquanto `RESUMO ANUAL` contém três lançamentos avulsos nas linhas 53–55. Esses registros e as células W132:W155 de dezembro que têm conteúdo são sinalizados para revisão, sem gerar lançamentos automáticos.

Os cabeçalhos devem existir antes de cada tabela: linhas 1–5 e 127–131. Layout diferente produz erro, em vez de tentar adivinhar silenciosamente. Limites: arquivo de 10 MB, até 80 MB descompactados, 3.000 partes ZIP, 10.000 linhas e 100 colunas por aba. O original enviado é removido após processamento, inclusive em erro. A prévia contém dados normalizados criptografados, é restrita à conta e expira em 30 minutos. Confirmação, cancelamento ou logout removem a prévia. Em produção, agende a limpeza das expiradas.

A substituição afeta **todos os lançamentos e limites do ano importado**, incluindo parcelas e previsões previamente criadas naquele ano; as regras de contas fixas e os outros anos são preservados. Faça um backup primeiro. Alterações no ano após gerar a prévia invalidam a confirmação para impedir sobrescrever trabalho recente.

## Backup

Exporte JSON em Configurações. O arquivo inclui anos, vínculos de saldo, categorias, limites, contas fixas e parcelas. Não inclui credenciais, senha ou prévias de importação. O JSON não é criptografado: guarde-o com cuidado.

Ao restaurar, confira as quantidades e confirme a substituição de **todos os anos**. A conta de acesso permanece. A validação de modelos e referências ocorre dentro de uma transação; qualquer erro restaura o estado anterior. Mudanças feitas depois da prévia impedem a restauração desatualizada. Exportação e restauração requerem autenticação.

## Testes e verificações

```bash
bundle exec rails test
bundle exec rails zeitwerk:check
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile
```

Os testes criam XLSX sintéticos temporários e os removem no final. Cobrem saldo, limites, separação de situações, cada coluna financeira, datas inferidas, fórmulas auxiliares, diferenças de limites mensais, validação, transações, substituição/cancelamento, conferência dos totais, parcelas, contas fixas, autenticação, filtros, telas e backup. O banco de teste é `storage/test.sqlite3`, separado do banco de uso.

Veja [docs/ARQUITETURA.md](docs/ARQUITETURA.md) para aprender como o código está organizado e [docs/PRODUCAO.md](docs/PRODUCAO.md) para publicar com armazenamento persistente.

## Referências

- [Rails 8.1.4.1 — versão estável usada](https://rubyonrails.org/2026/11/4/Rails-8.0.5.2-and-8.1.4.1-have-been-released)
- [Guias oficiais do Rails](https://guides.rubyonrails.org/v8.1/index.html)
- [Roo — leitura de planilhas](https://github.com/roo-rb/roo)
