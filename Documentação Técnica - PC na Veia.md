# 🗂️ PC na Veia

**Status:** Em andamento | **Período:** 28/09/2026 — 29/09/2026 | **Repositório:** https://github.com/AdaoElias/PCnaVeia

## 🎯 Resumo

Site estático de curso técnico de manutenção de computadores, com trilhas de aula, quizzes, checklists e anotações. Usa Supabase para autenticação e persistência do progresso por aluno, com painel exclusivo do instrutor. Publicado no GitHub Pages.

## 🎨 Proposta Inicial

Criar uma apostila digital interativa para alunos iniciantes em manutenção de PCs, cobrindo montagem, diagnóstico, instalação do Windows, malware e extras (introdução à informática, conectores, pendrive de boot). O diferencial seria a experiência guiada: conteúdo visual com fotos reais e vídeos, progresso salvo por conta, funcionamento offline-first e acompanhamento do instrutor. Público-alvo: iniciantes que querem aprender a montar, diagnosticar e manter computadores. A autenticação obrigatória foi adotada para vincular o progresso ao aluno e permitir o painel do instrutor.

## 🛠️ Stack Técnica

| Camada | Tecnologia | Versão |
|--------|-----------|--------|
| Backend | Supabase (BaaS) — Auth + REST/PostgREST | Serviço gerenciado |
| Frontend | HTML5, CSS3, JavaScript (vanilla, IIFE) | Sem framework |
| Banco | PostgreSQL (Supabase) | Serviço gerenciado |
| Infra | GitHub Pages + CDN jsDelivr | Estático |
| Autenticação | Supabase Auth (e-mail/senha + OAuth GitHub/Google) | supabase-js v2 |
| Segurança de dados | Row Level Security (RLS) + função `security definer` | PostgreSQL |
| Player de vídeo | YouTube no-cookie (iframe carregado sob demanda) | — |
| Ferramentas de apoio | Git, GitHub, SQL Editor do Supabase | — |

**Stack inferida a partir do código e das memórias:** site 100% front-end estático, sem build step, sem `package.json` e sem backend próprio; Supabase atua como backend-as-a-service (autenticação, banco relacional e API REST automática); deploy via GitHub Pages com `.nojekyll`; dependências externas apenas via CDN (`@supabase/supabase-js@2`) e iframes de vídeo.

## 🐛 Erros Encontrados & Corrigidos

| # | Erro | Causa Raiz | Solução | Lição |
|---|------|-----------|---------|-------|
| 1 | Atalho `L` disparava ao digitar "gmail" no campo de e-mail | Listener de teclado global sem verificação de foco em campo de texto | Adicionar guarda `!typing && DB` antes de tratar a tecla | Atalhos globais precisam ignorar inputs, textareas e contenteditable |
| 2 | View `my_progress_summary` retornava PGRST205 "Could not find the table" | View criada sem `GRANT SELECT`; o PostgREST oculta relações sem privilégio no schema cache | `grant select` para `authenticated` e `service_role`; alias `p.id as user_id` | Erro de "tabela inexistente" no PostgREST pode ser permissão, não ausência |
| 3 | Recursão de política RLS no painel do instrutor | Política consultava a própria tabela `profiles` que estava sendo filtrada | Função `public.is_instructor()` com `security definer` e `set search_path` | `security definer` quebra recursão de política RLS no Supabase |
| 4 | Upsert genérico falhava com "column does not exist" | Injeção automática de `updated_at` em tabelas que usam `answered_at` / `issued_at` | Remover injeção; usar triggers `set_updated_at` e colunas corretas por tabela | Conhecer o schema antes de generalizar um CRUD |
| 5 | Link de confirmação de e-mail caía em 404 | Site URL do Supabase sem o subdiretório `/PCNaVeia` do GitHub Pages | Ajustar Site URL e Redirect URLs em Authentication → URL Configuration | GitHub Pages publica em subdiretório; a origin sozinha perde o path |
| 6 | Proveedores OAuth desativados apareciam no login | UI renderizava botões fixos, sem consultar o que estava habilitado | Consultar `/auth/v1/settings` e ocultar providers inativos | Detectar capacidades em tempo de execução, não assumir configuração |
| 7 | Escritas falhavam silenciosamente no modo offline | `supabase-js` resolve com `{ error }` em vez de lançar exceção | Verificar `res.error` explicitamente e enfileirar em caso de falha | Não assumir que clientes HTTP sempre lançam erro |
| 8 | Diagramas SVG técnicos foram rejeitados pelo público | Conteúdo vetorial complexo demais para iniciantes | Substituir por fotos reais de montagem + vídeos de apoio | Validar a linguagem visual com o público antes de investir na produção |
| 9 | Foto do gabinete não atualizava no navegador | Cache agressivo do GitHub Pages (`max-age=600`) | Renomear o arquivo (`-v2`) para forçar novo caminho | Versionar nomes de assets para furar cache de CDN |

## ⭐ Avaliação da Stack

| Critério | Nota | Comentário |
|----------|------|-----------|
| Facilidade de aprendizado | 5 | HTML/CSS/JS + Supabase tem curva suave para quem já conhece front-end |
| Produtividade no desenvolvimento | 5 | BaaS elimina a necessidade de backend próprio e acelera a entrega |
| Documentação/Comunidade | 5 | Supabase, MDN e PostgREST têm documentação extensa e comunidade ativa |
| Performance percebida | 4 | Site estático é rápido, mas depende de CDN e iframes externos |
| Você usaria de novo? | Sim | Baixo custo operacional, deploy simples e RLS robusto para dados por usuário |

## 💡 Conclusões & Recomendações

- **Recomendaria esta stack para:** sites de conteúdo educacional, apostilas interativas e MVPs que precisam de autenticação e persistência por usuário sem manter servidor.
- **Evitaria se:** o requisito for funcionamento 100% offline (o Supabase exige rede para autenticar) ou se houver necessidade de processamento/segredos no servidor.
- **Aprendizado principal:** RLS bem modelado permite proteger dados diretamente no banco; separar papéis (`student` / `instructor`) com `security definer` resolve autorização sem backend dedicado.

## 🔖 Tags

`#html` `#css` `#javascript` `#supabase` `#postgresql` `#github-pages` `#vanilla-js` `#baas` `#rls`

---

## 🔎 Revisão Técnica — Inconsistências e Pontos de Atenção

1. **Status real:** o site está publicado e o painel do instrutor funciona, mas há pendências de segurança e OAuth — por isso "Em andamento", não "Concluído".
2. **Caminhos divergentes:** as memórias citam arquivos em `C:\Users\Adao_Elias\Desktop\Works\Treinamento`, mas o repositório atual está em `DEV 2.0\Curso PCNaVeia`. Atualizar a documentação para o caminho vigente.
3. **Contradição "offline":** o site se declara offline-first, porém autenticação (Supabase), SDK via CDN e vídeos (YouTube) exigem internet. Detalhar o que realmente funciona offline (apenas leitura de cache local).
4. **Segredo exposto:** a `SUPABASE_SECRET_KEY` foi exposta em chat e precisa ser rotacionada. A chave pública no front é aceitável, mas isso deve estar explícito na ficha.
5. **OAuth GitHub quebrado:** o `client_id` no Supabase está incorreto (usa e-mail em vez do `Iv1...`). Pendência funcional que impede login social.
6. **Certificados:** a tabela `certificates` existe, mas a emissão está fora do escopo atual. Documentar como funcionalidade futura ou remover da ficha de escopo.
7. **Acoplamento de configuração:** o e-mail do instrutor está hardcoded em `supabase-instructor.sql`. Parametrizar ou documentar claramente.
8. **Ausência de README/LICENSE:** o repositório não tem README nem licença. Recomendado adicionar instruções de deploy e configuração do Supabase.
9. **Sem testes automatizados:** não há `package.json`, lint ou testes. Para um projeto pequeno é aceitável, mas convém registrar como dívida técnica.
10. **Material interno versionado em dobro:** `BackUp/` contém cópias não versionadas e `.docx` são ignorados pelo `.gitignore` — confirmar que isso é intencional e remover duplicatas locais.
