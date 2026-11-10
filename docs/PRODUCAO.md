# Produção com dados persistentes

A aplicação sempre exige login, inclusive localmente. Para publicação na internet, use Rails em **production**, HTTPS e um volume persistente. Não use `rails server` em desenvolvimento exposto à internet.

## SQLite persistente

SQLite atende uma aplicação pessoal em uma única instância. O diretório do banco deve sobreviver a reinícios e novos deploys. Não use o filesystem temporário de plataformas sem disco persistente, nem compartilhe o mesmo arquivo SQLite por NFS entre vários servidores.

Defina no gerenciador de segredos/processos da hospedagem:

```text
RAILS_ENV=production
DATABASE_PATH=/var/lib/fluxo/production.sqlite3
SECRET_KEY_BASE=<segredo gerado por bin/rails secret>
RAILS_LOG_LEVEL=info
```

Crie `/var/lib/fluxo` com permissão de escrita apenas para o usuário do serviço. Guarde o mesmo `SECRET_KEY_BASE` entre deploys; sua troca invalida sessões e prévias criptografadas. Não versione esse segredo. Se houver proxy HTTPS terminando TLS, configure `BEHIND_PROXY=1` **somente** quando a aplicação só for acessível por esse proxy. Rails força HTTPS e cookies seguros em produção.

Com as variáveis exportadas no ambiente:

```bash
bundle config set --local without 'development test'
bundle install
bin/rails db:prepare
bin/rails assets:precompile
bin/rails account:setup
bin/rails server -b 127.0.0.1 -p 3000
```

Use um supervisor (systemd, contêiner ou serviço da hospedagem) e proxy reverso com certificado válido. Configure limite de upload HTTP de aproximadamente 12 MB. O parser aceita XLSX/JSON de até 10 MB. Sirva os assets de `public/assets`. Não publique a pasta `storage`, `log`, os backups nem arquivos `.env`.

Agende a cada 30 minutos, com o mesmo ambiente e usuário do serviço:

```bash
bin/rails previews:cleanup
```

A restrição de login usa o cache do Rails. Esta configuração é adequada a uma única instância; se migrar para vários processos/servidores, configure cache compartilhado e um banco de servidor antes de escalar.

## Contêiner opcional

O Dockerfile incluído usa Ruby 3.4.8, compila assets e roda com usuário sem privilégios. Execute da raiz do projeto, em uma máquina com Docker:

```bash
docker build -t fluxo-de-caixa .
docker volume create fluxo-data
# Defina SECRET_KEY_BASE no seu shell usando um segredo longo e aleatório.
docker run --rm -e RAILS_ENV=production -e SECRET_KEY_BASE \
  -v fluxo-data:/rails/storage fluxo-de-caixa bin/rails db:prepare
docker run --rm -it -e SECRET_KEY_BASE \
  -v fluxo-data:/rails/storage fluxo-de-caixa bin/rails account:setup
docker run -d --name fluxo -p 127.0.0.1:3000:3000 \
  -e SECRET_KEY_BASE -e BEHIND_PROXY=1 \
  -v fluxo-data:/rails/storage fluxo-de-caixa
```

O último comando pressupõe um proxy HTTPS local configurado. O contêiner não fornece certificado nem domínio. O build Docker não foi executado neste ambiente porque o usuário não tem acesso ao daemon; a aplicação e os assets foram testados diretamente em Ruby.

## Backups operacionais

Faça exportações JSON regularmente e antes de imports/restaurações. Para cópia física do SQLite ativo, use a API de backup do SQLite ou o comando `.backup`; não copie só o arquivo `.sqlite3` enquanto houver escrita, porque pode existir um WAL. Teste uma restauração em ambiente separado. JSON contém dados financeiros em texto claro: mantenha criptografia e controle de acesso no armazenamento de backups.

A restauração JSON é atômica e preserva a conta. Para recuperar uma senha, execute `bin/rails account:setup` no servidor. Não existe registro público nem redefinição por e-mail.

## Migrar para PostgreSQL no futuro

Se precisar de múltiplas instâncias, adicione a gem `pg`, configure `database.yml` para PostgreSQL usando `DATABASE_URL`, crie o banco e execute as migrations. Migre os dados por backup JSON numa janela sem escrita e confira os totais. Não basta apontar a variável `DATABASE_URL` mantendo o adaptador SQLite. Essa variante não está configurada nem validada nesta entrega; SQLite persistente é o caminho de produção documentado e implementado.
