# Sentinel — validação independente da reorganização

Estado: **PASS parcial; rota canónica incompleta. Não há aprovação global sem ressalvas.**
Escopo: leitura local + consulta read-only de bots; sem Studio (exclusivo Coder), jogo/config/assets, instalações, publicação ou restauro. Única escrita: este ficheiro.
Comandos: `git status --short`; `cat` de WORKFLOW/roles/sentinel, wrapper pipeline, SKILL pipeline/testing e references/qa; Python hashlib/JSON/tarfile; MCP `list_bots(computer="this", kind="codync", limit=20)`.

## Resultados
| Estado | Verificação | Evidência |
|---|---|---|
| PASS | Regras/limites | WORKFLOW e papel Sentinel lidos; um dono/ficheiro, exclusividade até para inspeção Studio, QA com evidência e aprovação visual só do Chefe. Nenhuma nova avaliação visual exigida: não há alterações visuais nesta tarefa. |
| PASS | Acesso a testing | `.agents/skills/roblox-testing/SKILL.md` lido; cópia `.claude` idêntica SHA-256; referência `references/cloud-test-runner.md` existe em ambas. LESSONS.md não existe para testing nem pipeline; não é uma omissão de leitura. |
| PASS | Acesso QA canónico | `tools/roclicks-skills/roblox-game-pipeline/SKILL.md` e `references/qa.md` lidos; wrapper Codync pipeline encaminha para o SKILL canónico existente. |
| PASS | Auditoria independente de cópias | Oito comparações canónico→cópia: 176 ficheiros comparados, zero diferenças, em concordância com skill-copy-audit.json. Manifesto canónico: 138/138 hashes atuais válidos. |
| PASS | Backup legível | Sete ficheiros presentes; dois TARs lidos integralmente sem extrair, sem paths de escape nem links. team-before contém os mesmos seis IDs e bindings-before seis entradas. Isto não é um teste de restauro. |
| PASS | Matriz configurada | Seis nomes/IDs únicos, pasta FreeAPet correta. Papéis abaixo coerentes com WORKFLOW e descrição Sentinel recebida. |
| PASS | Readback vivo dos outros cinco bots | list_bots confirmou IDs, cwd e descrição completa exatamente iguais a team-configured.json para Atlas/Coder/Pixel/Terra/Nova. |
| BLOCKED | Readback vivo independente do próprio Sentinel | list_bots não devolve este bot; não há get_bot disponível. Papel confirmado pela configuração local e atualização autoritativa recebida, mas não se conta como sexto readback MCP independente. |
| FAIL | Generalização da rota canónica | `tools/roclicks-skills/roblox-testing/SKILL.md` não existe. A instrução comum de carregar todos os recursos nesse prefixo não cobre testing; acesso local funciona. Fonte/fallback deve ser explicitada, sem inventar/mover/instalar recursos nesta auditoria. |
| NOT RUN | Restauro e runners | Nenhum restauro, teste do jogo, Jest/Lune/Open Cloud ou instalação: fora de escopo. Archives legíveis não provam recuperação de uma configuração em execução. |
| NOT RUN | Studio/visual | Studio não chamado; sem alteração visual, não é necessária nova aprovação ou screenshot. Aprovação visual final continua exclusivamente do Chefe. |

## Matriz de papéis
| Bot | Responsabilidade verificada | Readback |
|---|---|---|
| Atlas | pipeline / coordenação | Config + descrição MCP completa |
| Coder | Luau / arquitetura / sistemas | Config + descrição MCP completa |
| Pixel | direção artística / VFX / studify | Config + descrição MCP completa |
| Terra | mapa / biomas / terreno / iluminação | Config + descrição MCP completa |
| Nova | UI / ui-maker | Config + descrição MCP completa |
| Sentinel | testing / QA / segurança e performance sob demanda | Config + perfil recebido; MCP próprio não exposto |

## Cópias: resultados independentes
| Skill | Cópia | Canónico/cópia | Diferenças |
|---|---|---:|---:|
| roblox-game-pipeline | `.agents/skills` | 11/11 | 0 |
| roblox-game-pipeline | `.claude/skills` | 11/11 | 0 |
| studify | `.agents/skills` | 4/4 | 0 |
| studify | `.claude/skills` | 4/4 | 0 |
| roblox-ui-maker | `.agents/skills` | 53/53 | 0 |
| roblox-ui-maker | `.claude/skills` | 53/53 | 0 |
| roblox-vfx | `.agents/skills` | 20/20 | 0 |
| roblox-vfx | `.claude/skills` | 20/20 | 0 |

## Backup: prova de leitura (sem extrair/restaurar)
| Arquivo | Membros/ficheiros | Bytes descomprimidos lidos | SHA-256 |
|---|---:|---:|---|
| `working-files.tar.gz` | 375/374 | 24722957 | `6fce98275628e6c1a71c96deae57e262b09da4ac02d6f24ca3f385de76207705` |
| `codync-skills.tar.gz` | 9/4 | 1966 | `fe6162496213a620d5cc8dcc53b6ba208e585b1fef203bc9466fb9710fc979f3` |

Os restantes elementos existem e têm conteúdo: `working-tree.patch` (2 467 213 bytes), `git-status.txt`, `head.txt`, `team-before.json`, `codync-bindings-before.json`. O TAR de trabalho inclui alterações preexistentes (16 ficheiros sob src) e cópias de skills; o TAR Codync inclui os quatro wrappers anteriores. Sem restore sobre alterações posteriores e sem reset --hard.

## Riscos/contradições e resolução
1. **Rota canónica:** testing tem fallback local completo, mas não existe no clone RoClicks. O mesmo padrão pode afetar skills locais do Coder; a auditoria de quatro cópias não afirma cobrir todas as skills disponíveis. Atlas deve documentar a exceção/fonte. Não é necessário interromper o acesso QA via `.agents` já verificado.
2. **Defaults de outros projetos:** pipeline manda criar GAME.md, impor meshlab/estilo e executar fases; WORKFLOW explicitamente limita esta reorganização e prevalece. Esses passos não foram executados nem convertidos em mecânicas/requisitos FreeAPet.
3. **Portabilidade QA:** `qa.md` contém cliques y+58/pixels pela metade e nomes de tools de outro bridge. São exemplos dependentes do ambiente: em futuras rondas usar capacidades, viewport e coordenadas reais, sem aplicá-los cegamente. Não há falha visual nova nesta auditoria.
4. **Separação de ownership:** Pixel agora possui VFX; Terra ambiente, Nova layout, Coder comportamento. Isto substitui a atribuição histórica de VFX à Terra; configuração dos outros cinco bots confirma a mudança.
5. **Integridade temporal:** checksums identificam os ficheiros desta auditoria; trabalho anterior/alheio já estava modificado no Git. Nenhum desses ficheiros foi editado. Não se certifica o working tree inteiro como limpo nem todas as ferramentas de todos os agentes.

## Hashes de referência
| Caminho | SHA-256 |
|---|---|
| `docs/agent-workflow/WORKFLOW.md` | `ca1e953632c44d9ed1cb6eac07405704adca02f9826bd2c1c42bd4d508f86e8a` |
| `docs/agent-workflow/roles/sentinel.md` | `2f2245c4edc666a379443eb99a664a95f417192cbc3403ea2354c2ed43b54b09` |
| `docs/agent-workflow/team-configured.json` | `edb6150288842b4c6a366fe5ecec57297f1f5f672fad7b512c278b39b7e69612` |
| `docs/agent-workflow/skill-copy-audit.json` | `5dc99bda9d48a6d9da0f3032011a195d89084bf32b13512bf2df9dd4c48ac28c` |
| `docs/agent-workflow/roclicks-manifest.json` | `b8a406c5393c6a8704df5734bf0f3896738ad17fa4383179dd365d01b9b6415e` |
| `.agents/skills/roblox-testing/SKILL.md` | `44a7da48e3ecae98dcbdbc0e88e363c0256f03548eea419d9c955d57bdf78f2a` |
| `tools/roclicks-skills/roblox-game-pipeline/references/qa.md` | `443b4882c4e06c0cbd4b95bf5b0f52bc6f0aa5ae2973ae0e226886650ba229dc` |

## Fecho
**Alterado:** só evidência QA. **Testado:** leitura/hash/JSON/TAR e cinco readbacks vivos, conforme resultados acima. **Pendente:** documentar rota testing e obter readback próprio se houver API adequada; restauro NOT RUN. **Ficheiros modificados:** `docs/agent-workflow/evidence/sentinel.md`.
