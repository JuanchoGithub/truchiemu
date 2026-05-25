---
layout: default
title: "Depurando o Invisível: Por que Jogos de Dreamcast Não Conseguiram Salvar"
description: Uma análise técnica aprofundada sobre como corrigir salvamentos VMU do Dreamcast no Flycast - ciclos de vida de opções de core, semântica da API libretro e análise binária.
last_updated: Maio 2026
---

# Depurando o Invisível: Por que Jogos de Dreamcast Não Conseguiram Salvar no Nosso Emulador

Passamos a maior parte de uma semana rastreando um bug onde jogos de Dreamcast no TruchiEmu simplesmente não conseguiam salvar. Nenhuma mensagem de erro, nenhum crash — apenas silêncio. O VMU (Visual Memory Unit, o cartão de memória do Dreamcast) simplesmente não existia tanto quanto os jogos se preocupavam. O que se seguiu foi uma jornada através de análise binária de código fechado, semântica da API libretro e uma única string errada que se propagou para uma falha total. Aqui está como encontramos e corrigimos.

---

## O Problema de Memória do Dreamcast

O Dreamcast é incomum entre os consoles na medida em que seus cartões de memória — VMUs — são conectados ao controle, não ao console. Cada controle possui dois slots de expansão, e o VMU vai no slot 1. Da perspectiva do emulador, isso significa que o VMU não é um simples arquivo no disco — é um **dispositivo de barramento maple** que precisa ser explicitamente criado e anexado a uma porta do controle em tempo de execução.

O Flycast, o core libretro que usamos para emulação de Dreamcast, gerencia isso através de seu sistema de opções. Opções de core como `reicast_device_port1_slot1` controlam o que está conectado em cada slot. Os valores possíveis são: `VMU`, `Purupuru` (um pacote de vibração), `DreamPotato` (um periférico de terceiros) e `None`. Se o slot 1 de um controle não estiver configurado como `VMU`, os jogos não têm onde salvar. Esse era nosso problema.

---

## A Configuração: Como Pensávamos que Funcionava

Tínhamos um arquivo `CoreOverrides.json` que definia valores padrão para opções de core — coisas como modo de renderização, threading e atribuições de portas de dispositivos. Para o Dreamcast, configuramos o slot 1 de cada controle como `"Visual Memory"`, porque é isso que o rótulo da opção diz na interface:

```json
"reicast_device_port1_slot1": "Visual Memory"
```

Parece razoável, certo? "Visual Memory" é o que o Flycast mostra em seu menu de opções. É o nome pelo qual todos conhecem o VMU. Também estava completamente errado.

---

## Armadilha #1: Rótulos vs. Valores

A API de opções de core do libretro possui um conceito de **valores** e **rótulos**. Valores são o que o código compara. Rótulos são o que os humanos veem em um menu. Eles frequentemente são diferentes, especialmente para opções com caracteres especiais, preocupações de localização ou nomenclatura legada.

Descobrimos isso da forma mais difícil fazendo um despejo hexadecimal do binário do Flycast:

```
0x57d4c6: VMU
0x57d4ca: Purupuru
0x57d4d3: DreamPotato
0x57d4df: None
```

Estas são as strings de **valor** — o que `update_variables()` do Flycast realmente passa para `strcmp()`:

```cpp
if (!strcmp("VMU", var.value))
config::MapleExpansionDevices[port][slot] = MDT_SegaVMU;
else if (!strcmp("Purupuru", var.value))
config::MapleExpansionDevices[port][slot] = MDT_PurupuruPack;
```

`"Visual Memory"` nunca corresponde. Não `VMU`, não `Purupuru`, não nada. Cai em todas as ramificações. Mas fica pior. Como `var.value` não é NULL — é `"Visual Memory"`, uma string real — o padrão de fallback que teria configurado um VMU também é ignorado. O código assume que se o valor não correspondeu a nenhuma opção conhecida, foi intencionalmente configurado para algo incomum. O resultado: a configuração do dispositivo de expansão nunca é atualizada, e o Flycast volta ao seu padrão interno, que é **Purupuru** (um pacote de vibração). Sem VMU. Sem salvamentos. A correção foi uma linha no CoreOverrides.json, mas encontrá-la exigiu análise binária porque o código-fonte libretro do Flycast tinha divergido do binário compilado real que estávamos executando.

> **Lição:** Na API libretro, valores e rótulos de opções são coisas separadas. Sempre use o valor, não o rótulo, ao configurar opções programaticamente. Se você está trabalhando com um binário que não compilou, verifique as strings reais.

---

## Armadilha #2: A Guarda de Primeira Inicialização

Mesmo após corrigir o valor para `"VMU"`, havia um problema de temporização. A função `update_variables()` do Flycast possui um parâmetro `first_startup`:

```cpp
static void update_variables(bool first_startup)
{
config::Settings::instance().load(false);
// ... processa muitas opções ...

if (!first_startup) {
// Opções de porta de dispositivo SÓ processadas aqui
for (int port = 0; port < 4; port++) {
// lê opções reicast_device_port*_slot*
// configura MapleExpansionDevices conforme apropriado
}
devices_need_refresh = true;
}
}
```

Durante `retro_load_game()`, o Flycast chama `update_variables(true)`. As opções de porta de dispositivo são **ignoradas inteiramente** na primeira chamada. A justificativa faz sentido: durante a inicialização, o core não inicializou totalmente sua emulação de hardware, então configurar dispositivos maple prematuramente poderia causar problemas. Em vez disso, o Flycast cria dispositivos com seus padrões internos (Purupuru no slot 1) e adia as atribuições de porta de dispositivo configuradas pelo usuário para uma chamada posterior.

Isso significa que nossa substituição `"VMU"` estava em `g_optValues`, pronta para ser retornada, mas o Flycast nunca a solicitou durante a única leitura de opções que aconteceu antes dos dispositivos serem criados.

> **Lição:** Cores libretro não necessariamente leem todas as suas opções ao mesmo tempo. Algumas opções são bloqueadas pelo estado de inicialização. Você precisa entender o ciclo de vida específico de leitura de opções do core, não apenas o contrato da API.

---

## Armadilha #3: O Sinal de Atualização de Variável

A API libretro fornece `RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE` — um callback que o core consulta para verificar se os valores das opções mudaram desde a última leitura. Se retornar `true`, o core deve reler suas opções. O Flycast verifica isso no início de cada `retro_run()`:

```cpp
void retro_run()
{
bool updated = false;
if (environ_cb(RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE, &updated) && updated)
update_variables(false); // first_startup=false — portas de dispositivo AGORA processadas

if (devices_need_refresh)
refresh_devices(false); // chama maple_ReconnectDevices()

if (first_run)
emu.start(); // inicia emulação com dispositivos corretos

// ... renderiza quadro ...
first_run = false;
}
```

Esta é a sequência-chave: `update_variables(false)` → `refresh_devices(false)` → `emu.start()`. Se pudéssemos sinalizar `GET_VARIABLE_UPDATE = true` após `retro_load_game()` mas antes do primeiro `retro_run()`, o Flycast releria as opções com `first_startup=false`, processaria as atribuições de porta de dispositivo, criaria VMUs e então iniciaria a emulação com a configuração de dispositivos correta.

Mas o callback do TruchiEmu sempre retornava `false`. Não tínhamos mecanismo para dizer ao Flycast "ei, suas opções mudaram." Nossa correção: uma flag global configurada após `retro_load_game()`:

```objc
// LibretroBridgeImpl.mm — após retro_load_game() para cores Flycast
if (g_coreID && [[g_coreID lowercaseString] containsString:@"flycast"]) {
g_variablesUpdated = YES;
[self setControllerPortDevice:1 device:device_type];
[self setControllerPortDevice:2 device:device_type];
[self setControllerPortDevice:3 device:device_type];
}
```

```objc
// LibretroCallbacks.mm — handler GET_VARIABLE_UPDATE
case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
{
bool updated = g_variablesUpdated;
if (updated) {
g_variablesUpdated = NO; // consome a flag — retorna true uma vez
}
if (data)
*(bool *)data = updated;
return true;
}
```

A flag é **consumida na leitura**. Ela retorna `true` exatamente uma vez, depois reseta. Isso aciona `update_variables(false)` do Flycast no primeiro quadro, que processa as opções de porta de dispositivo, que detecta nosso valor `"VMU"`, que configura `MDT_SegaVMU`, que aciona `refresh_devices(false)`, que chama `maple_ReconnectDevices()`, que recria todos os dispositivos maple com VMUs no slot 1. Então `emu.start()` executa, e o Dreamcast inicializa com cartões de memória.

> **Lição:** A API libretro é uma conversa, não um arquivo de configuração. Alguns cores precisam ser *informados* para reler opções; eles não farão isso sozinhos. Entender quais sinais da API acionam quais transições de estado internas é crítico.

---

## Armadilha #4: Valores de Opções Lidos Sem GET_VARIABLE

Como se os problemas de temporização não fossem suficientes, alguns cores libretro leem valores de opções através de caminhos de código internos que não passam por `RETRO_ENVIRONMENT_GET_VARIABLE` de forma alguma. Eles acessam seu sistema de configuração diretamente. Para lidar com isso, adicionamos **pré-carregamento** — injetando substituições JSON diretamente no dicionário `g_optValues` no momento da inicialização do core, antes que o Flycast consulte qualquer coisa:

```objc
void core_override_apply_all_to_optvalues(const char* coreID) {
if (!coreID || !g_optValues) return;
NSString* coreStr = [NSString stringWithUTF8String:coreID];
NSDictionary* allOverrides = [CoreOverrideBridge getAllOverridesFor:coreStr];
if (!allOverrides || allOverrides.count == 0) return;

for (NSString* key in allOverrides) {
NSString* value = allOverrides[key];
if (key.length > 0 && value.length > 0) {
g_optValues[key] = value;
}
}
}
```

Isso é chamado a partir de `applyPersistedOverrides()`, que executa durante `SET_CORE_OPTIONS`. A camada de substituição é:

1. **Substituições JSON** (nossos padrões) — aplicadas primeiro
2. **Substituições .cfg** (escolhas salvas do usuário) — aplicadas por cima, sempre vencendo

Isso garante que nossos padrões de VMU estejam em vigor para qualquer caminho de código que o Flycast use para ler opções, enquanto ainda respeita qualquer configuração explícita do usuário.

> **Lição:** Ao fazer a ponte entre dois sistemas (um aplicativo Swift e um core de emulador C++), você não pode assumir que toda comunicação passa pela API oficial. Caminhos de código internos podem contornar seus callbacks. Pré-carregamento defensivo garante consistência independentemente de qual caminho o core tome.

---

## Armadilha #5: Arquivos VMU Ausentes e Corrompidos

Mesmo com todas as correções de software acima, os VMUs não funcionarão se os arquivos de salvamento reais não existirem no disco. O Flycast procura arquivos VMU no diretório de sistema (`system/dc/`), especificamente arquivos como `vmu_save_A1.bin` até `vmu_save_D1.bin`. Cada um deve ter exatamente 128KB — um sistema de arquivos FAT12 devidamente formatado com 200 blocos livres.

Empacotamos arquivos VMU pré-formatados em `dreamcast.zip` junto com os arquivos de BIOS, e estendemos `DreamcastBIOSService` para extraí-los e validá-los:

```swift
private func repairCorruptVMUFiles() {
for file in vmuFiles {
let url = dcDirectory.appendingPathComponent(file)
guard fm.fileExists(atPath: url.path) else { continue }

// Tamanho errado? Excluir e re-extrair
if size != vmuExpectedSize {
try? fm.removeItem(at: url)
continue
}

// Tudo zeros? (O Flycast pode zerar VMUs em desligamento incorreto)
if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
data.allSatisfy({ $0 == 0 }) {
try? fm.removeItem(at: url)
}
}
}
```

A verificação de corrupção é importante. Descobrimos que quando o Flycast desliga sem desmontar corretamente o sistema de arquivos VMU (por exemplo, se o usuário forçar o encerramento), ele pode gravar um arquivo zerado. Um arquivo de 128KB de todos zeros passa na verificação de tamanho, mas é um sistema de arquivos corrompido. Os jogos o veem como um cartão não formatado e não conseguem salvar. Nossa lógica de reparo detecta isso e re-extrai o VMU íntegro do pacote.

> **Lição:** Cores de emulador podem corromper seus próprios arquivos de salvamento. Validar a integridade do arquivo (não apenas a existência) é essencial para uma experiência confiável.

---

## O Bug da Guarda Invertida

Enquanto depurávamos a extração do VMU, encontramos um erro de lógica em `ensureExtracted()` que estava silenciosamente impedindo que os arquivos VMU fossem implantados:

```swift
// ANTES — lógica invertida: retorna antecipadamente quando os arquivos ESTÃO AUSENTES
guard hasAllFiles && hasAllVMUFiles else { return }

// DEPOIS — correto: retorna antecipadamente apenas quando todos os arquivos ESTÃO PRESENTES
if hasAllFiles && hasAllVMUFiles { return }
```

O padrão `guard ... else { return }` retorna quando a condição é **falsa** — ou seja, quando os arquivos estão ausentes. A função estava saindo exatamente quando deveria estar extraindo arquivos. Este era um clássico problema do Swift: `guard` é projetado para retorno antecipado em **falha**, mas a lógica foi escrita como se fosse uma instrução `if` para **sucesso**.

> **Lição:** A instrução `guard` do Swift inverte o fluxo de controle comparado ao `if`. Sempre verifique a direção do retorno antecipado ao converter entre os dois.

---

## A Cadeia Completa

Aqui está o que acontece agora quando um jogo de Dreamcast é iniciado no TruchiEmu:

1. **Inicialização do aplicativo** — `DreamcastBIOSService.ensureExtracted()` valida e extrai arquivos VMU para `system/dc/`
2. **Carregamento do core** — `SET_CORE_OPTIONS` → `parseCoreOptionsV2()` armazena padrões de opções em `g_optValues`
3. **Pré-carregamento de substituições** — `core_override_apply_all_to_optvalues()` grava `"VMU"` em `g_optValues` para todas as entradas device port slot1
4. **`retro_load_game()`** — O Flycast chama `update_variables(true)` → opções de porta de dispositivo **ignoradas** (first_startup) → dispositivos criados com padrões Purupuru
5. **Pós-carregamento** — O TruchiEmu configura `g_variablesUpdated = YES` + chama `setControllerPortDevice` para as portas 1-3
6. **Primeiro `retro_run()`** — O Flycast consulta `GET_VARIABLE_UPDATE` → retorna `true` → `update_variables(false)` → opções de porta de dispositivo **processadas** → `strcmp("VMU", "VMU")` corresponde → `MapleExpansionDevices` configurado como `MDT_SegaVMU` → `devices_need_refresh = true`
7. **Mesmo quadro** — `refresh_devices(false)` → `maple_ReconnectDevices()` → controles recriados com VMUs no slot 1
8. **Mesmo quadro** — `emu.start()` → emulação começa com VMUs equipados
9. **Jogo salva** → grava em `system/dc/vmu_save_A1.bin`

Da perspectiva do usuário, simplesmente funciona. O jogo vê cartões de memória, os salvamentos acontecem, e os arquivos estão lá na próxima vez que ele inicializar.

---

## O Que Aprendemos

**Análise binária às vezes é inevitável.** Não conseguíamos descobrir por que `"Visual Memory"` não estava funcionando apenas a partir do código-fonte — o binário que estávamos executando tinha divergido do código-fonte mais recente. Despejos hexadecimais e buscas de strings eram a única maneira de encontrar as strings de valor reais.

**A API libretro é enganosamente simples.** `GET_VARIABLE` parece um armazenamento de chave-valor, mas a realidade é que os cores têm ciclos de vida complexos de leitura de opções com guardas de inicialização, sinais de atualização e caminhos de código internos que contornam a API inteiramente. Você precisa entender o comportamento específico de cada core.

**Integração de emulador é integração profunda.** Você não está apenas passando configuração para uma biblioteca — você está fazendo a ponte entre dois ambientes de execução com ciclos de vida diferentes, gerenciamento de estado diferente e suposições diferentes sobre quem é dono do quê. Os bugs vivem nas lacunas entre esses ambientes.

**Os bugs mais difíceis são os silenciosos.** Sem crash, sem mensagem de erro, sem linha de log. Apenas um cartão de memória que não existe. A correção foi uma única string em um arquivo JSON, mas encontrar essa string exigiu entender todo o ciclo de vida de leitura de opções de um core de emulador de código fechado.

---

## Arquivos Alterados

| Arquivo | Mudança |
|---------|---------|
| `TruchiEmu/Resources/Config/CoreOverrides.json` | `"Visual Memory"` → `"VMU"` para todas as entradas `*_device_port*_slot1` |
| `TruchiEmu/Core/Engine/LibretroCallbacks.mm` | Handler `GET_VARIABLE_UPDATE` retorna a flag `g_variablesUpdated` |
| `TruchiEmu/Core/Engine/LibretroGlobals.h` | Adicionada declaração `extern BOOL g_variablesUpdated` |
| `TruchiEmu/Core/Engine/LibretroGlobals.mm` | Adicionada definição `BOOL g_variablesUpdated = NO` |
| `TruchiEmu/Core/Engine/LibretroBridgeImpl.mm` | Configura `g_variablesUpdated = YES` + `setControllerPortDevice` para portas 1-3 após `retro_load_game()` (apenas Flycast) |
| `TruchiEmu/Core/Engine/CoreOverrideBridge.h` | Declarada `core_override_apply_all_to_optvalues()` |
| `TruchiEmu/Core/Engine/CoreOverrideBridge.mm` | Implementada `core_override_apply_all_to_optvalues()` — injeta substituições JSON em `g_optValues` |
| `TruchiEmu/Resources/System/dreamcast.zip` | Adicionados 4 arquivos VMU pré-formatados de 128KB (`vmu_save_A1.bin` até `vmu_save_D1.bin`) |
| `TruchiEmu/Services/DreamcastBIOSService.swift` | Lógica de extração, validação e reparo de corrupção de VMU |