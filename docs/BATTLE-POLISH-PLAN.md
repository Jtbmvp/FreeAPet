> **Nota (2026-11-07):** documento histórico em parte. O roubo de pets saiu do jogo, que agora assenta em batalhas, e o código entra no Studio pela MCP, não pelo plugin do Rojo. Em caso de conflito, prevalece `docs/DECISIONS.md`.

# Polimento das batalhas e da UI: auditoria e plano

Estado: **aprovado** (28 out 2026). Feito: 1, 2, 4 (+ Acorn Squirrel), 5, 6 (parte da batalha). Feito também: ataques das 6 criaturas (C01–C18) e pontos da equipa. Falta: 3 (pets v3, precisa dos GLB), ataques dos iniciais (depois de terem ataques na Config) e compactar as outras janelas.
Catálogo de animações e VFX com prompts: `docs/VFX-CATALOGUE.md`.

## 1. O que li

**Claude Design** (projeto `81af58e5…`, lido pela API do projeto no browser):

- `CLAUDE.md` do projeto: o kit v3. Cada pet é um corpo esculpido único, com uma malha suave e skinned (até 20k triângulos, 1 MeshPart no Roblox). Tem ossos `jnt_*` com pesos automáticos e partes rígidas só para olhos, garras, folhas e água. A textura de studs vai na cor e no normal map. Idle (2.4 s) e Walk (0.8 s) são por IK nas folhas. Tamanhos estão em metros, com o pet virado para +Z.
- Todos os `<pet>-v3.js` (META, rig, notas). Não li a geometria (SCULPT/PARTS), para poupar tokens.
- Props/mapa (`props-v3.js`, `props-kits-v3.js`, `cliffs-v3.js`): existem, mas **não lhes toquei**, porque o mapa não está acabado.

| Pet | Raridade | Grupo | Altura | Olhos | Ossos especiais | Ideia |
|---|---|---|---|---|---|---|
| **Spoutle** | Common | **Neutral Starter** | 2.5 m | — | `jnt_spout`, cauda 1–4 | Cão-fonte: bacia de pedra na cabeça com 3 jatos a brilhar, colar dourado com estrela, cauda com gota a brilhar |
| **Glimmouse** | Common | **Neutral Starter** | 1.4 m | sparkle | orelhas, cauda 1–4 | Jerboa aos saltos: orelhas de cristal rosa em aro dourado, cauda-chicote com cristal dourado |
| **Plazadillo** | Common | **Neutral Starter** | 1.8 m (3 m de comprido) | button | `jnt_crystal` | Tatu com carapaça de calçada (5 faixas, juntas douradas), esmeralda no topo, garras douradas |
| Acorn Squirrel | Common | Forest | 1.3 m | focus | `jnt_acorn`, cauda | De pé, abraça uma bolota, capacete de bolota, anéis âmbar na cauda |
| Hopping Mushroom | Uncommon | Forest | 2.1 m | blank | `jnt_cap`, `jnt_baby` | Rabugento, chapéu vermelho com 2 cogumelos bebés, botas vermelhas |
| Branch Deer | Rare | Forest | 3.8 m | noble | `jnt_antler` | Veado nobre, hastes em lira com hera e folhas de outono |
| Running Cactus | Common | Desert | 2.0 m | cartoon | `jnt_flower` | Saguaro de calções-vaso, braços que bombeiam, flor rosa a brilhar |
| Ball Scorpion | Uncommon | Desert | 3.0 m | slit | `jnt_pinch`, cauda | Placas areia/ferrugem com juntas âmbar, pinças serrilhadas, ferrão |
| Sun Camel | Rare | Desert | 4.0 m | noble | `jnt_neck2` | Dromedário rei, manta vermelha, coroa-sol com disco a brilhar |

**Skills lidas:** roblox-collaboration-mode, roblox-camera, roblox-animation-vfx e roblox-gui.
**Figma:** o servidor Figma precisa de autorização (`/mcp`), e o jogo não tem ficheiro Figma. As skills Figma trabalham sobre ficheiros Figma, por isso não as consigo aplicar. Aplico as mesmas regras de design system (tokens e componentes) diretamente no `UITheme`.

## 2. O que existe e fica

- **`BattleService`** (servidor, 949 linhas): decide tudo — ordem, dano, cápsulas, XP, troca, fuga, defesa do dono. Monta o arranjo da arena: o centro olha do jogador para o selvagem, o nosso pet fica a 7 studs do centro, o jogador a 12 atrás dele, e há um anel de 28 segmentos Neon com raio de 15. Este arranjo **já é o da imagem de referência** (jogador de costas → o nosso pet → o inimigo).
- **Eventos para o cliente:** `effect` = super / weak / capture / escape / faint / levelup / switch, com `actor`, `target`, `damage` e `moveType`. **É a base de todo o VFX.** Não muda.
- **Ações:** 4 ataques, Pet Capsule (comprar e atirar), Switch, Run. Passam a **Attack / Bag / Switch / Run**, com os 4 ataques dentro de Attack. A lógica não muda.
- **`UITheme` stud** (feito ontem), dados da leaderboard (`leaderstats` "Cash/s") e Idle/Walk dos 6 pets (`PetAnimator`, Motor6D).

## 3. O que está fraco hoje

- **Câmara:** um corte seco para uma vista lateral fixa (`setCamera`). Não há intro, revelação, contagem nem regresso suave.
- **Ataques:** o mesmo para todos — avanço de 3 studs, faíscas genéricas e tremor do alvo. Não há antecipação, impacto forte, números de dano, hit flash nem shake de câmara.
- **Cápsula:** uma esfera azul. Desmaiar é rodar 80°.
- **UI de batalha:** 7 botões soltos (4 ataques + 3), cartões de vida sem XP nem equipa, mensagem grande no topo.
- **Pets no jogo:** são a versão **v2** (MeshParts rígidas, 33–73 peças). As **v3** do Claude Design ainda não estão no jogo.

## 4. Limitações técnicas (honestas)

1. **A arte do mapa está fundida por material.** `Map.Art` tem 465 MeshParts, e 115 delas medem mais de 150 studs. Por exemplo, uma só malha de 362×92×485 tem todas as árvores de uma cor da floresta. **Esconder uma árvore esconde a floresta inteira.** As árvores, arbustos e cactos só existem separados em `Map.Collision`, que são Parts invisíveis.
   → Com o mapa atual:
   - escondo o que é separado: pets soltos, outros jogadores e as equipas deles, FX e etiquetas;
   - viro a arena para o ângulo mais limpo, testado com raycasts contra os troncos e copas de `Map.Collision`;
   - aproximo a câmara quando algo tapa.

   → **Com o mapa novo, a ocultação de árvores e pedras funciona por objeto**, se os props vierem como modelos separados (fica a nota para o export do mapa novo). O sistema fica pronto para isso.
2. **Importar os pets v3:** é preciso exportar o GLB de cada folha e importá-lo no Studio com o **3D Importer**. O MCP não o consegue correr, e o `upload_asset` falha sem chave Open Cloud. São malhas skinned (Bones, não Motor6D), por isso o `PetAnimator` passa a escrever `Bone.Transform` em vez de `Motor6D.Transform`.
3. **Animações:** as folhas só têm **Idle e Walk**. **Não existe nenhuma animação de ataque, dano, desmaio ou vitória.** Até as criares, cada ataque usa uma animação procedural de reserva (avanço, golpe e regresso) com o VFX próprio por cima.
4. **Treinador inimigo:**
   - Batalhas selvagens não têm treinador, e não vou inventar um.
   - Nas batalhas de roubo, o dono pode estar até 120 studs, não na arena. Pô-lo atrás do pet é mexer na personagem dele (decisão B).
5. **Iniciais:** no Claude Design, os 3 dizem "Neutral Starter". O DESIGN-v2 §5 diz 1 Forest, 1 Desert e 1 Neutro (decisão A). Ainda não têm ataques nem ecrã de escolha. As batalhas continuam desligadas no jogo publicado.
6. **Estados:** não há queimar, gelar, atordoar nem buffs nas batalhas. O catálogo não lhes inventa VFX. Só tem a cura (fonte) e o Release Shield, que existem.
7. **Pet Capsule:** o modelo existe em `props-v3.js`, mas disseste que só os pets estão acabados, por isso **fica a esfera** até dizeres.
8. **Telemóvel:** o simulador de aparelhos do Studio não funciona neste Linux. As verificações de ecrã pequeno são por contas.
9. **Som:** fica de fora, como pediste.

## 5. Plano de implementação (fase 3)

Tudo no cliente, exceto o que vai marcado. Os eventos e as regras do servidor não mudam.

1. **Câmara cinematográfica + intro**
   - `Client/Battle/BattleCamera.luau`: planos com os enquadramentos calculados pelo tamanho real de cada pet (`GetExtentsSize`), mexidos no `PreRender` e com evasão de oclusão.
   - **Plano de jogo:** por cima do ombro, atrás e à direita do jogador, a olhar para o ponto entre os dois pets, puxado para o inimigo. FOV ~55.
   - `Client/Battle/BattleIntro.luau`, cerca de 5 s:

     | Tempo | O que acontece |
     |---|---|
     | 0–0.6 s | Entrada, o anel acende |
     | 0.6–1.8 s | O nosso pet de frente, em contrapicado |
     | 1.8–3.0 s | O inimigo de frente (com o dono atrás, se a decisão B for "sim") |
     | 3.0–4.6 s | Contagem 3-2-1 |
     | 4.6–5.1 s | FIGHT! |
     | 5.1–5.7 s | Assenta no plano de jogo e a UI entra |

   - Tocar ou clicar salta a intro. Em Settings fica "Short intro" (só a contagem).
   - *Servidor:* o primeiro turno do defensor só conta depois da intro. Ao montar a arena, escolhe o ângulo mais limpo.
2. **Ocultação local** (`Client/Battle/BattleObstacles.luau`)
   - Recolhe os candidatos uma vez no início: dentro do anel + margem, e no cone da câmara.
   - Usa `LocalTransparencyModifier` nas Parts e Decals, e desliga localmente ParticleEmitters, BillboardGuis e SurfaceGuis.
   - Guarda os valores originais e repõe tudo quando a batalha acaba, é cancelada, o jogador morre ou sai. Nunca toca no chão, nos 2 pets, nos jogadores da batalha nem no anel.
   - Aceita a tag `BattleHideable` para os props do mapa novo.
3. **Pets v3**
   - **Tu:** exportas os 9 GLB das folhas. **Eu:** preparo o Blender, o nome e a escala; tu importas com o 3D Importer.
   - Depois: `AnimalFactory` e `PetAnimator` passam a Bones, as alturas vêm do `TARGET_H` e o Idle/Walk dos GLB.
   - Os v2 ficam como reserva até cada v3 entrar.
4. **Ataques modulares**
   - `Client/Battle/Fx/Common.luau` tem os efeitos universais. `Client/Battle/Fx/Moves/<SpeciesId>.luau` tem uma função por ataque.
   - `Fx.Play(move, ctx)`: usa o clip `Attack_<Move>` se existir (com marcador `impact`), senão a reserva.
   - Inclui uma ferramenta de pré-visualização só no Studio, para testar cada efeito sem lutar.
   - *Servidor:* o `fighterView` passa a mandar `xp` e `xpToNext`, para a barra de EXP.
5. **Leaderboard compacta**
   - A tecla **Tab** abre e fecha; está fechada ao início. No telemóvel há um botão "pódio" pequeno.
   - Cabeçalho stud pequeno, corpo escuro a 35% de transparência e colunas Player | Cash/s.
   - Aro ouro, prata ou bronze na cara do top 3; a tua linha fica realçada.
   - Atualiza ao entrar e sair jogadores e quando os valores mudam. **Só Cash/s**, que é o único valor que existe.
6. **UI**
   - **Batalha:** 4 botões grandes, Attack / Bag / Switch / Run, em 2×2 com ícones grandes (espada, saco, setas, sapatilha). Attack abre os 4 ataques com a cor do tipo e os usos, com botão Voltar.
   - **Cartões de vida compactos:** inimigo em cima à esquerda, nós em baixo à esquerda, com nível, HP, EXP e pontos da equipa (até 3). A mensagem passa a ser pequena.
   - **Resto:** janelas mais pequenas (a Trade vazia tem 780×580), ícones maiores e o mesmo espaçamento em todo o lado.

## 6. Decisões precisas (uma de cada vez)

- **A.** Os 3 iniciais são todos Neutro, como no Claude Design, ou 1 Forest, 1 Desert e 1 Neutro, como no DESIGN-v2?
- **B.** Numa batalha de roubo com o dono a defender, ponho a personagem dele atrás do pet durante a batalha? Proposta: **não mexer**, mostrar só o nome dele no cartão.
- **C.** Usamos já o modelo Pet Capsule do `props-v3.js`, ou fica a esfera até o mapa estar pronto?

## 7. Testes (fase 4)

**No Studio (solo):**
- as 4 ações;
- a intro a ser saltada e a acabar a meio, com fuga e morte;
- a câmara com o pet mais pequeno (Glimmouse 1.4 m) e o maior (Sun Camel 4 m);
- reposição de tudo o que foi escondido;
- Tab;
- 3 resoluções simuladas por tamanho de janela.

**Só por análise:**
- dois jogadores em batalhas separadas — o Studio fica sem memória com 2 clientes;
- telemóvel real;
- ocultação de árvores — só funciona com o mapa novo.
