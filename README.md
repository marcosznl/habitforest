# HabitForest

Rastreador de hábitos nativo para macOS no estilo Forest: cada hábito é uma árvore que cresce com a sequência, perde folhas quando você falha um dia e seca quando a sequência quebra.

Requer macOS 14+ e Xcode 16+ (testado no Xcode 27.1).

## Abrir e compilar

```bash
brew install xcodegen   # só se for regenerar o projeto
xcodegen generate       # recria HabitForest.xcodeproj a partir do project.yml
open HabitForest.xcodeproj
```

1. Em **Signing & Capabilities**, escolha o seu Team nos dois alvos (`HabitForest` e `HabitForestWidget`), ou preencha `DEVELOPMENT_TEAM` no `project.yml`. O App Group (`$(TeamIdentifierPrefix)com.marcosznl.habitforest`) depende de um Team real. Sem ele, o widget não enxerga os dados do app.
2. Rode o esquema **HabitForest** (⌘R).

## Mecânicas

| Sequência | Estágio |
|---|---|
| 0 | Semente |
| 1–3 | Broto |
| 4–14 | Árvore Jovem |
| 15–30 | Adulta |
| 30+ | Ancestral |

- **Saúde:** `.healthy` (em dia) → `.struggling` (1 dia falhado; a sequência ainda pode ser salva) → `.withered` (2 dias seguidos falhados; a sequência zera).
- **Estufa:** pausa o hábito nas férias. Os dias pausados não contam e não quebram a sequência, mesmo depois de sair da estufa (ficam gravados como `HabitLog.isFrozen`).
- **Hábitos:** cada linha mostra a árvore do hábito (clique nela para trocar a espécie), as últimas duas semanas e o botão **Regar** de hoje.
- **Floresta:** ilha isométrica que começa vazia e ganha uma árvore a cada dia regado (últimos 60 dias), no estágio daquele dia: brotos no começo da sequência, árvores maiores depois. Dias não regados não deixam árvores mortas.
- **Diário:** ao regar o dia de hoje abre-se um campo de uma linha (`HabitLog.dailyNote`).
- **Cenário:** a luz do fundo muda conforme o horário (manhã, tarde, pôr do sol, noite), a ilha e as árvores mudam com a estação (grama, areia de outono, neve; o hemisfério é detectado pela região ou definido em Ajustes) e o clima é sorteado por dia (chuva, neve, pétalas, folhas, vaga-lumes).

## Integrações com o macOS

| Recurso | Onde |
|---|---|
| Janela sem bordas, translúcida, opcionalmente sempre no topo | `App/Windows/MainWindowController.swift` |
| Barra de menus + atalho global ⌘⇧H | `StatusItemController.swift`, `HotKeyManager.swift`, `MenuBarPopoverView.swift` |
| Feedback tátil no trackpad | `Managers/Haptics.swift` |
| Filtros de Foco (Trabalho / Pessoal / Não Perturbe) | `Intents/AppIntents.swift` (`HabitFocusFilter`) |
| Notificações com “Regar Árvore” / “Adiar 15 min” | `Managers/NotificationManager.swift` |
| Som ambiente (chuva, vento, floresta) e efeitos, sintetizados em tempo real | `Managers/AudioManager.swift` |
| Blocos de foco no Calendário, sincronização com Lembretes nos dois sentidos | `Managers/EventKitManager.swift` |
| Retrato da Floresta (PNG) e backup JSON pelo menu Compartilhar | `Managers/ExportService.swift` |
| Widget interativo na mesa | `Widget/HabitWidget.swift` |
| Mapa de calor de 365 dias e conclusão por dia da semana | `Views/HeatmapView.swift` |
| Atalhos / Siri | `ToggleHabitIntent`, `StartFocusIntent`, `OpenForestIntent` |

**Lembretes:** com a sincronização ligada (Ajustes › Integrações), cada hábito vira um lembrete diário na lista HabitForest, criado com um dia de antecedência. Marcar ou desmarcar no Lembretes, no Mac ou no iPhone, rega ou desrega a árvore, e o contrário também vale. Com o app aberto (inclusive só na barra de menus) a sincronização acontece na hora; com o app fechado, os últimos 14 dias são conciliados na próxima abertura. Para ficar sempre aberto, ligue **Abrir ao iniciar sessão** em Ajustes › Geral.

O Filtro de Foco é configurado em **Ajustes do Sistema › Foco › (um Foco) › Filtros de Foco › HabitForest**. Nele você escolhe qual contexto de hábitos aparece e se os lembretes ficam silenciados.

## Visual

- 12 espécies desenhadas em código (incluindo Ipê-Amarelo, Palmeira e Baobá), chapadas em duas tonalidades, cada uma com seu próprio broto e evolução até a ancestral, e variações de outono e inverno.
- Fontes: **Rubik** (títulos) e **Inter** (texto), as mesmas do site do Forest, ambas com licença OFL e empacotadas em `Shared/Fonts`.
- Ícone gerado a partir do mesmo desenho das árvores. Para gerar de novo:

```bash
swiftc -parse-as-library -o /tmp/gerar-icone Tools/GerarIcone/main.swift Shared/Core/*.swift Shared/Rendering/*.swift
/tmp/gerar-icone App/Resources/Assets.xcassets/AppIcon.appiconset
```

## Persistência

O banco SwiftData fica em `~/Library/Mobile Documents/com~apple~CloudDocs/HabitForest/HabitForest.store`. Se o iCloud Drive não estiver disponível, ou se a opção estiver desligada em Ajustes › Dados, ele vai para `~/Library/Application Support/HabitForest/`.

Por isso o app principal **não usa App Sandbox**: um app em sandbox não consegue gravar nessa pasta do iCloud Drive. O widget, que é obrigatoriamente sandboxed, não abre o banco. Ele lê um snapshot JSON no App Group, e os toques no widget entram numa fila que o app aplica ao banco (`Shared/Core/PendingActionQueue.swift`).

Use o banco em um Mac por vez: o iCloud Drive sincroniza o arquivo SQLite inteiro e não mescla alterações feitas ao mesmo tempo em dois Macs.

## Estrutura

```
App/        app principal (modelos SwiftData, store, managers, views, intents, janelas)
Shared/     compilado no app e no widget (lógica de sequência, árvores, ilha, cenário, fontes, snapshot, ToggleHabitIntent)
Widget/     extensão WidgetKit
Tools/      gerador do ícone
project.yml especificação do XcodeGen
```
