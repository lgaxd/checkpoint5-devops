# Roteiro de gravação — DimDim no Azure

Este roteiro segue os requisitos do checkpoint: mostrar o tutorial de implantação completo, com criação dos recursos em nuvem, o deploy acontecendo, a aplicação Web funcionando, CRUD nas duas tabelas com verificação no Azure SQL após cada operação e o monitoramento no Application Insights e no banco. Reserve **15 a 25 minutos**, além de qualquer demora excepcional da Azure. Grave em **720p ou superior**, com explicação falada.

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

## Sequência de gravação e fala sugerida

| Tempo aproximado | O que mostrar | Fala sugerida |
|---|---|---|
| **00:00–00:45** | Apresente o projeto e a tela inicial da aplicação. | “Este é o DimDim, uma aplicação Web em Java 21 para gerenciar usuários e fazendas. Ela será publicada no Azure App Service, usará Azure SQL como banco PaaS relacional e Application Insights para telemetria.” |
| **00:45–01:30** | Mostre brevemente o README, a arquitetura e as pastas `src/`, `scripts/` e `docs/`. Não abra o `.env`. | “A solução inclui interface Web, API, duas tabelas relacionadas, DDL, scripts de implantação e testes. O deploy será feito pela Azure CLI com `az webapp deploy`; o banco é Azure SQL, não containerizado.” |
| **01:30–07:30** | Comece a captura do terminal e execute `bash scripts/azure-deploy.sh`. Mantenha visíveis o início, as etapas de criação ou reutilização dos recursos, os testes Maven, o envio do pacote e o resultado final do health check. A duração varia conforme a Azure; pode acelerar somente os períodos de espera na edição, mantendo evidentes o comando executado e os resultados. | “Agora estou executando o tutorial de implantação do repositório. O script cria ou reutiliza o Resource Group, o Azure SQL Server e database, o App Service Linux com Java 21 e o Application Insights. Em seguida inicializa o schema e o usuário restrito do banco, executa os testes e empacota a aplicação.” |
| **07:30–08:15** | Mostre o trecho `az webapp deploy` sendo executado e depois a mensagem `Deploy e smoke test concluídos`. Oculte na edição o ID da subscription e o IPv4, se aparecerem. | “O pacote está sendo enviado ao App Service com `az webapp deploy`. O smoke test confirma que o endpoint de health responde e que a aplicação consegue acessar o banco.” |
| **08:15–09:00** | No portal Azure, mostre o Resource Group com App Service Plan, Web App, SQL Server/database e Application Insights; abra o Web App para mostrar status e região. | “Estes são os recursos criados para a solução. O Web App está executando Java 21, e o SQL é um serviço Azure PaaS separado, na região configurada para o projeto.” |
| **09:00–09:45** | Abra a URL `https://561413-dimdim-webapp.azurewebsites.net/` e `/actuator/health`. Registre a conta fictícia para entrar na interface; se mostrar o cadastro, consulte também o usuário recém-criado no SQL. | “A interface Web está hospedada na nuvem e não em localhost. O health check retorna `UP`; agora vou autenticar com dados fictícios para demonstrar as operações e a persistência.” |
| **09:45–12:15** | Faça CREATE, READ, UPDATE e DELETE de um usuário pela interface. **Depois de cada ação**, mude para o terminal, rode a consulta SQL correspondente e mostre o resultado. Para READ, abra a listagem e confirme o mesmo registro no banco. | “Em cada etapa, além do resultado da interface, verifico diretamente a tabela `TB_USUARIO` no Azure SQL: o registro criado, o registro lido, os valores atualizados e a ausência da linha após a exclusão.” |
| **12:15–15:00** | Faça CREATE, READ, UPDATE e DELETE de uma fazenda, associando-a a um usuário existente. **Depois de cada ação**, rode a consulta SQL correspondente. Nas consultas, mostre também o usuário associado à fazenda. | “Agora faço o mesmo CRUD na tabela `TB_FAZENDA`. A consulta relaciona fazenda e usuário pela chave estrangeira; depois da exclusão confirmo que o registro saiu do banco.” |
| **15:00–17:00** | No Application Insights, mostre requests e dependências gerados durante o deploy e o CRUD. Depois, no recurso Azure SQL Database, abra as métricas ou a tela de monitoramento disponíveis para o banco. Se os gráficos ainda estiverem vazios, atualize a página após gerar requests e consultas. | “O Application Insights recebeu telemetria da aplicação, incluindo requisições e dependências. Aqui também estou mostrando o monitoramento do Azure SQL Database, conforme exigido no checkpoint.” |
| **17:00–17:30** | Volte à aplicação ou ao Resource Group e encerre. | “A demonstração cobriu a implantação, a aplicação Web, o CRUD com confirmação de cada operação no Azure SQL e o monitoramento do App e do banco. Depois de guardar as evidências, vou remover os recursos para evitar custos.” |

Os horários são uma referência. Não elimine etapas para caber em um tempo fixo; o requisito do checkpoint é que as evidências estejam no vídeo.

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
