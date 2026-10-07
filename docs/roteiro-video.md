# Roteiro de gravação — DimDim no Azure

Este roteiro segue os requisitos do checkpoint: mostrar o tutorial de implantação completo, com criação dos recursos em nuvem, o deploy acontecendo, a aplicação Web funcionando, CRUD nas duas tabelas com verificação no Azure SQL após cada operação e o monitoramento no Application Insights e no banco. Reserve **20 a 30 minutos**, além de qualquer demora excepcional da Azure. Grave em **720p ou superior**, com explicação falada.

> **Segurança:** não mostre `.env`, senhas, tokens JWT, connection strings ou dados pessoais reais. O script de deploy também imprime o ID da subscription e o IPv4 usado na regra temporária do SQL; oculte esses trechos na captura ou desfoque-os na edição, sem cortar a execução do deploy. Não use `set -x`.

## Preparação antes da gravação

Faça os preparativos fora da gravação para evitar pausas, mas **não faça o deploy antes**: a gravação precisa mostrar a execução real do script.

1. Confirme que a subscription e a região autorizada estão selecionadas. Este projeto está configurado para `chilecentral`; confira disponibilidade e quota na subscription antes do vídeo. Não exiba o `.env`.
2. Confira o `CLIENT_IP` público atual, os nomes dos recursos e as credenciais no `.env`, sem imprimir nem compartilhar seus valores. O nome do Web App deve estar disponível globalmente.
3. No WSL ou Git Bash, abra a raiz do projeto e confira as ferramentas e a subscription ativa:

   ```bash
   cd /mnt/c/Users/LGA/Documents/checkpoint5-devops/cp4-devops
   export PATH="$PATH:/opt/mssql-tools18/bin"
   az account show --query name --output tsv
   java -version
   command -v az sqlcmd curl zip
   ```

   Se `sqlcmd` não estiver em `/opt/mssql-tools18/bin`, ajuste o `PATH` conforme a instalação local.
4. Teste a conectividade com o banco e prepare uma conta fictícia para autenticar na interface. Use uma senha temporária exclusiva para o vídeo, não reutilizada em nenhum outro lugar.
5. Deixe abertos, mas fora da captura até o momento certo:
   - VS Code na raiz do projeto e no `README.md`;
   - terminal no WSL/Git Bash, na raiz do projeto;
   - portal Azure com acesso ao Resource Group `561413-dimdim-rg`;
   - navegador pronto para a URL do Web App;
   - Azure SQL Query Editor ou o terminal preparado para `sqlcmd`.
6. Use registros de demonstração consistentes durante o vídeo. Exemplo: usuário `Ana Silva`, e-mail fictício `ana-demo-20261006@example.com`, e fazenda `Fazenda Horizonte`. Se repetir a gravação, escolha outro e-mail ainda não usado.

### Preparar a consulta SQL sem expor a senha

No terminal da gravação, carregue as variáveis e defina este atalho antes de começar o CRUD. O `source` não imprime o conteúdo do `.env`; `SQLCMDPASSWORD` evita passar a senha como argumento visível do `sqlcmd`. Não habilite o modo de rastreamento do shell.

```bash
set -a
source .env
set +a

sqlcheck() {
  SQLCMDPASSWORD="$SQL_ADMIN_PASSWORD" sqlcmd \
    -S "tcp:${SQL_SERVER_NAME}.database.windows.net,1433" \
    -d "$SQL_DATABASE_NAME" \
    -U "$SQL_ADMIN_USERNAME" \
    -N \
    -Q "$1"
}
```

Confirme antes de gravar que `sqlcheck "SELECT TOP 1 ID_USUARIO FROM dbo.TB_USUARIO;"` conecta sem erro. Para cada operação do CRUD, execute a consulta correspondente abaixo e deixe o resultado legível na gravação.

## Sequência de gravação (ação ↔ fala)

Regra do roteiro: **toda fala tem uma ação na tela ao mesmo tempo**. A única exceção são as esperas do deploy (marcadas como ⏳), em que se narra o que o script está fazendo sem ação nova. Leia a fala enquanto executa a ação da mesma linha.

### Parte 1 — Apresentação e explicação do `azure-deploy.sh` (≈ 3 min)

| # | Ação na tela | Fala sugerida |
|---|---|---|
| 1.1 | Mostrar o `README.md` no VS Code e a árvore `src/`, `scripts/`, `docs/` (sem abrir o `.env`). | “Este é o DimDim, aplicação Web em Java 21 / Spring Boot para gerenciar usuários e fazendas. Vai rodar no Azure App Service, com Azure SQL como banco PaaS e Application Insights para telemetria.” |
| 1.2 | Abrir `scripts/azure-deploy.sh` no topo (carga do `.env` e validações iniciais). | “Todo o deploy é feito por um único script, `azure-deploy.sh`. Ele carrega as variáveis do `.env` (que não vou mostrar), valida o IP e confere se estou logado no Azure CLI.” |
| 1.3 | Rolar até `az group create` e `az sql server create` / `az sql db create`. | “Primeiro ele cria o Resource Group, registra os providers, cria o SQL Server e o banco Basic, e libera o firewall para o Azure e para o meu IP, temporariamente.” |
| 1.4 | Rolar até `az appservice plan create` e `az webapp create`. | “Depois cria o App Service Plan Linux B1 e o Web App com Java 21, somente HTTPS.” |
| 1.5 | Rolar até `azure-sql-init.sh` e `az monitor app-insights component create`. | “Em seguida executa o DDL das duas tabelas e cria um usuário restrito para a aplicação, sem privilégio de administrador. Também cria o Application Insights.” |
| 1.6 | Rolar até `appsettings set` e `mvnw clean test package`. | “As configurações vão como app settings, sem segredos no código. Então o script roda os testes e gera o JAR.” |
| 1.7 | Rolar até `az webapp deploy` e o loop de health check. | “O pacote, com o agente do Application Insights, é enviado com `az webapp deploy`, e o script faz um smoke test no `/actuator/health`, que também valida a conexão com o banco.” |

### Parte 2 — Execução do deploy (≈ 8–10 min)

Abrir o terminal na raiz do projeto, com `export PATH="$PATH:/opt/mssql-tools18/bin"`. **Não interrompa (Ctrl+C) em nenhum momento.** Esperas de 2–5 min com timeouts de `curl` são normais.

| # | Ação na tela | Fala sugerida |
|---|---|---|
| 2.1 | Executar `bash scripts/azure-deploy.sh`. | “Vou executar o script agora.” |
| 2.2 | ⏳ Aparece “Criando ou atualizando recursos…”. | “Está criando o Resource Group, registrando providers e criando o SQL Server e o banco.” |
| 2.3 | ⏳ Aparece a regra `AllowTemporaryClientIP`. (Oculte o IP na edição.) | “O firewall foi aberto temporariamente para o meu IP, para o script poder aplicar o schema.” |
| 2.4 | ⏳ Aparecem “Creating App Service Plan” e a criação do Web App. | “Agora o plano Linux e o Web App com Java 21.” |
| 2.5 | ⏳ “Inicializando o schema…”, “Aplicando DDL…”, “Azure SQL inicializado”. | “O DDL com `TB_USUARIO` e `TB_FAZENDA` foi aplicado e o usuário restrito da aplicação foi criado.” |
| 2.6 | ⏳ Saída do Maven com testes e `BUILD SUCCESS`. | “Os testes passaram e o JAR foi empacotado.” |
| 2.7 | ⏳ “Enviando o pacote…”, “Warming up Kudu…”. | “O pacote está sendo enviado ao App Service.” |
| 2.8 | ⏳ “Aguardando o App Service responder…” com timeouts de `curl`. | “O primeiro start do Java no plano B1 com o agente de telemetria leva alguns minutos; os timeouts são esperados, o script segue tentando.” |
| 2.9 | Aparece “Aplicação saudável…” e “Deploy e smoke test concluídos”. | “O health check respondeu `UP`, incluindo o banco. Deploy concluído.” |
| 2.10 | Abrir o portal Azure no Resource Group `561413-dimdim-rg`, mostrando plano, Web App, SQL Server/database e Application Insights. | “Estes são os recursos criados pelo script, na região configurada.” |

### Parte 3 — Front-end, cadastro e CRUD com `sqlcmd` (≈ 8–10 min)

Antes, no terminal, carregar `.env` e definir `sqlcheck` (seção abaixo), sem exibir segredos.

| # | Ação na tela | Fala sugerida |
|---|---|---|
| 3.1 | Abrir `https://561413-dimdim-webapp.azurewebsites.net/` no navegador. | “A interface está hospedada na nuvem, não em localhost.” |
| 3.2 | Na tela de login, usar a opção de **cadastro** com a conta fictícia (Ana Silva / e-mail demo) e entrar. | “Vou me cadastrar com dados fictícios e autenticar.” |
| 3.3 | Terminal: `sqlcheck` do **CREATE de usuário**. | “Conferindo direto no Azure SQL: o usuário cadastrado está em `TB_USUARIO`.” |
| 3.4 | Interface: abrir a listagem de usuários. Terminal: mesma consulta. | “A listagem mostra o mesmo registro que existe no banco.” |
| 3.5 | Interface: editar o nome para `Ana Souza`. Terminal: `sqlcheck` do UPDATE. | “Atualizei o nome e o banco já mostra o novo valor.” |
| 3.6 | Interface: criar `Fazenda Horizonte` associada ao usuário. Terminal: `sqlcheck` do CREATE de fazenda (JOIN). | “Criei a fazenda, e o JOIN confirma a ligação com o usuário pela chave estrangeira.” |
| 3.7 | Interface: listar fazendas. Terminal: mesma consulta. | “A fazenda lida na interface é a mesma persistida no banco.” |
| 3.8 | Interface: editar para `Fazenda Horizonte II`. Terminal: `sqlcheck` do UPDATE de fazenda. | “Atualização persistida e associação mantida.” |
| 3.9 | Interface: excluir a fazenda. Terminal: `sqlcheck` do DELETE de fazenda (sem linhas). | “A fazenda foi excluída e não existe mais no banco.” |
| 3.10 | Interface: excluir o usuário. Terminal: `sqlcheck` do DELETE de usuário (sem linhas). | “Por último, excluo o usuário, respeitando a ordem da chave estrangeira, e confirmo a ausência da linha.” |

### Parte 4 — Monitoramento e encerramento (≈ 3 min)

| # | Ação na tela | Fala sugerida |
|---|---|---|
| 4.1 | Application Insights `561413-dimdim-insights` → **Logs**, executar a consulta `requests`. | “O Application Insights recebeu as requisições que acabei de gerar.” |
| 4.2 | Executar a consulta `dependencies`. | “Aqui estão as dependências, incluindo as chamadas ao Azure SQL.” |
| 4.3 | Abrir o recurso Azure SQL Database → **Monitoring/Métricas**. | “Este é o monitoramento do banco. Descrevo apenas o que está preenchido na tela.” |
| 4.4 | Voltar ao Resource Group. | “Cobrimos o deploy, a aplicação Web, o CRUD com confirmação no SQL após cada operação e o monitoramento de App e banco. Agora removo os recursos para evitar custos.” |

Se a ingestão do Application Insights estiver vazia, gere novos acessos, espere um pouco e atualize antes de falar sobre os dados.
## Conferência no Azure SQL após cada operação

Execute uma consulta logo depois de **cada** ação na interface. Substitua o e-mail pelo valor exato usado na gravação e mantenha o filtro igual nas consultas de usuário.

### Usuário — `dbo.TB_USUARIO`

Após **CREATE**, confirme a nova linha:

```bash
sqlcheck "SELECT ID_USUARIO, NM_USUARIO, DS_EMAIL FROM dbo.TB_USUARIO WHERE DS_EMAIL = 'ana-demo-20261006@example.com';"
```

Após **READ**, mostre a listagem do usuário na interface e rode a mesma consulta para evidenciar que o registro lido está persistido no Azure SQL.

Após **UPDATE**, confirme os valores atualizados (por exemplo, nome `Ana Souza`):

```bash
sqlcheck "SELECT ID_USUARIO, NM_USUARIO, DS_EMAIL FROM dbo.TB_USUARIO WHERE DS_EMAIL = 'ana-demo-20261006@example.com';"
```

Após **DELETE**, confirme que a consulta não retorna linhas:

```bash
sqlcheck "SELECT ID_USUARIO, NM_USUARIO, DS_EMAIL FROM dbo.TB_USUARIO WHERE DS_EMAIL = 'ana-demo-20261006@example.com';"
```

### Fazenda — `dbo.TB_FAZENDA`

Crie a fazenda associada ao usuário escolhido na interface. Use o nome `Fazenda Horizonte` também no filtro abaixo.

Após **CREATE**, confirme a fazenda e a relação com seu usuário:

```bash
sqlcheck "SELECT f.ID_FAZENDA, f.NM_FAZENDA, f.DS_CIDADE, f.DS_ESTADO, f.NR_AREA_HECTARES, u.ID_USUARIO, u.NM_USUARIO FROM dbo.TB_FAZENDA f JOIN dbo.TB_USUARIO u ON u.ID_USUARIO = f.ID_USUARIO WHERE f.NM_FAZENDA = 'Fazenda Horizonte';"
```

Após **READ**, mostre a fazenda na interface e rode a mesma consulta para confirmar que o registro lido está persistido e ligado ao usuário correto.

Após **UPDATE**, use o nome efetivamente salvo (por exemplo, `Fazenda Horizonte II`) para confirmar os novos valores e a associação:

```bash
sqlcheck "SELECT f.ID_FAZENDA, f.NM_FAZENDA, f.DS_CIDADE, f.DS_ESTADO, f.NR_AREA_HECTARES, u.ID_USUARIO, u.NM_USUARIO FROM dbo.TB_FAZENDA f JOIN dbo.TB_USUARIO u ON u.ID_USUARIO = f.ID_USUARIO WHERE f.NM_FAZENDA = 'Fazenda Horizonte II';"
```

Após **DELETE**, confirme a ausência da fazenda:

```bash
sqlcheck "SELECT ID_FAZENDA, ID_USUARIO, NM_FAZENDA FROM dbo.TB_FAZENDA WHERE NM_FAZENDA = 'Fazenda Horizonte II';"
```

Exclua primeiro a fazenda e só depois o usuário associado, para respeitar a relação entre as tabelas. Se a gravação incluir a exclusão desse usuário, confirme também a ausência dele em `TB_USUARIO`.

## Mostrar o monitoramento

No Application Insights `561413-dimdim-insights`, abra **Transaction search** ou **Logs** depois de acessar a interface e executar as operações. Para logs, use:

```kusto
requests
| where timestamp > ago(30m)
| project timestamp, name, resultCode, success, duration
| order by timestamp desc
```

Para dependências, incluindo chamadas originadas pela aplicação:

```kusto
dependencies
| where timestamp > ago(30m)
| project timestamp, name, target, resultCode, success, duration
| order by timestamp desc
```

A ingestão pode levar alguns minutos. Se ainda não houver dados, gere acessos na aplicação, espere e atualize a consulta. Em seguida, abra o recurso **Azure SQL Database** no portal e mostre a área **Monitoring/Métricas** e as métricas disponíveis para o banco. Explique o que aparece na tela; não afirme que uma métrica ou gráfico está preenchido se não estiver.

## Checklist antes de encerrar

- [ ] O vídeo tem pelo menos 720p e explicação falada.
- [ ] A gravação mostra a execução do How To e o comando real `bash scripts/azure-deploy.sh`.
- [ ] É possível ver a criação ou reutilização dos recursos, os testes/build e o envio por `az webapp deploy`, além do smoke test final.
- [ ] A interface Web hospedada no Azure está funcionando; não é uma demonstração somente em localhost ou somente de API.
- [ ] CREATE, READ, UPDATE e DELETE foram mostrados para **cada** tabela, com consulta ao Azure SQL após cada operação.
- [ ] O relacionamento entre usuário e fazenda está visível no banco.
- [ ] O vídeo mostra Application Insights com telemetria e o monitoramento do Azure SQL Database.
- [ ] `.env`, senha, token, connection string, ID da subscription, IPv4 público e dados pessoais não ficam expostos.
- [ ] O vídeo foi revisado, salvo e publicado; o link está disponível para o PDF de entrega.

## Depois de gravar

1. Revise o vídeo e corte ou desfoque qualquer valor sensível que tenha aparecido, em especial o ID da subscription ou IPv4 impresso pelo deploy.
2. Salve/publique o vídeo e preencha o link em [`entrega.md`](entrega.md), junto com os dados do repositório.
3. Guarde o vídeo e as evidências antes de excluir qualquer recurso.
4. Remova os recursos após salvar e revisar as evidências, para evitar cobranças:

   ```bash
   cd /mnt/c/Users/LGA/Documents/checkpoint5-devops/cp4-devops
   bash scripts/azure-teardown.sh
   ```

   Confirme no prompt o nome exato do Resource Group. O teardown remove os recursos e os dados Azure; não o execute antes de concluir a gravação e guardar as evidências.
