-- Зависимости MoonLoader и внешние библиотеки
require 'lib.moonloader'
local imgui = require 'mimgui'
local sampev = require 'lib.samp.events'
local vkeys = require 'vkeys'
local encoding = require 'encoding'
local inicfg = require 'inicfg'
local ffi = require 'ffi'
local faicons = require 'fAwesome6'

-- Конфигурация скрипта
local CONFIG = {
    iniFilename = 'RepFlowCFG.ini',      -- Имя файла конфигурации
    scriptVersion = "3.2 | Premium",     -- Версия скрипта
    defaultKeyBind = 0x5A,               -- Клавиша активации по умолчанию: Z
    defaultKeyBindName = 'Z',            -- Название клавиши по умолчанию
    afkCooldown = 30,                    -- Задержка перед ловлей после AFK (сек)
    tag = "{1E90FF} [RepFlow]: {FFFFFF}", -- Тег сообщений скрипта
    tagInfo = "{1E90FF} [Информация]: {FFFFFF}", -- Тег информационных сообщений
}

-- Утилиты ImGui
local new = imgui.new                    -- Сокращение для создания объектов ImGui

-- Данные ChangeLog
local changelogEntries = {
    {
        version = "3.2 | Premium",
        description = [[
            - Оптимизирована производительность (меньше wait).
            - Добавлена статистика в инфо-окно.
            - Улучшена защита от флуда с настройкой паузы.
            - Добавлено логирование в файл.
        ]]
    },
    {
        version = "3.1 | Premium",
        description = [[
            - Новый стиль меню.
            - ChangeLog теперь разделён на две версии.
            - HF-1.0: Исправлены грамматические ошибки.
            - HF-1.1: Налажен цвет плиток, исправлены грамматические ошибки.
        ]]
    },
}

-- Глобальные состояния
local STATE = {
    keyBind = CONFIG.defaultKeyBind,
    keyBindName = CONFIG.defaultKeyBindName,
    lastDialogId = nil,
    reportActive = false,
    lastOtTime = 0,
    active = false,
    startTime = 0,
    gameMinimized = false,
    wasActiveBeforePause = false,
    afkExitTime = 0,
    changingKey = false,
    moveWidget = false,
    reportAnsweredCount = 0,
    lastDialogTime = os.clock(),
    manualDisable = false,
    reportAttempts = 0, -- Новая статистика
    floodCooldown = 0,  -- Время паузы после флуда
}

-- Настройки интерфейса и поведения
local SETTINGS = {
    otInterval = new.int(10),
    dialogTimeout = new.int(600),
    floodPause = new.int(10), -- Пауза после флуда (сек)
    otIntervalBuffer = new.char[5](tostring(10)),
    dialogTimeoutBuffer = new.char[5](tostring(600)),
    floodPauseBuffer = new.char[5](tostring(10)),
    useMilliseconds = new.bool(false),
    hideFloodMsg = new.bool(true),
    autoStartEnabled = new.bool(true),
    dialogHandlerEnabled = new.bool(true),
    infoWindowVisible = false,
    cursorVisible = false,
    mainWindowState = new.bool(false),
    infoWindowState = new.bool(false),
    activeTab = new.int(0),
    disableAutoStartOnToggle = false,
}

-- Разрешение экрана
local sw, sh = getScreenResolution()

-- Кодировка
encoding.default = 'CP1251'
local u8 = encoding.UTF8

-- Конфигурация по умолчанию
local defaultConfig = {
    main = {
        keyBind = string.format("0x%X", CONFIG.defaultKeyBind),
        keyBindName = CONFIG.defaultKeyBindName,
        otInterval = 10,
        useMilliseconds = false,
        dialogTimeout = 600,
        floodPause = 10,
        dialogHandlerEnabled = true,
        autoStartEnabled = true,
        otklflud = false,
    },
    widget = {
        posX = 400,
        posY = 400,
    }
}

-- Загрузка и применение конфигурации
local ini = inicfg.load(defaultConfig, CONFIG.iniFilename)
STATE.keyBind = tonumber(ini.main.keyBind) or CONFIG.defaultKeyBind
STATE.keyBindName = ini.main.keyBindName or CONFIG.defaultKeyBindName
SETTINGS.otInterval[0] = tonumber(ini.main.otInterval) or 10
SETTINGS.useMilliseconds[0] = ini.main.useMilliseconds or false
SETTINGS.dialogTimeout[0] = tonumber(ini.main.dialogTimeout) or 600
SETTINGS.floodPause[0] = tonumber(ini.main.floodPause) or 10
SETTINGS.dialogHandlerEnabled[0] = ini.main.dialogHandlerEnabled or true
SETTINGS.autoStartEnabled[0] = ini.main.autoStartEnabled or true
SETTINGS.hideFloodMsg[0] = ini.main.otklflud or false

-- Цветовая схема интерфейса
local COLORS = {
    leftPanel = imgui.ImVec4(27 / 255, 20 / 255, 30 / 255, 1.0),   -- Левый прямоугольник
    rightPanel = imgui.ImVec4(24 / 255, 18 / 255, 28 / 255, 1.0),  -- Правый прямоугольник
    childPanel = imgui.ImVec4(18 / 255, 13 / 255, 22 / 255, 1.0),  -- Child-окно
    hover = imgui.ImVec4(63 / 255, 59 / 255, 66 / 255, 1.0),       -- Наведение на кнопки
}

-- Основной цикл скрипта
function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end
    sampRegisterChatCommand("arep", cmd_arep)
    sampAddChatMessage(CONFIG.tag .. 'Скрипт {00FF00}загружен.{FFFFFF} Активация меню: {00FF00}/arep', -1)
    show_arz_notify('success', 'RepFlow', 'Успешная загрузка. Активация: /arep', 9000)
    logToFile("Скрипт загружен")

    while true do
        wait(100) -- Увеличиваем интервал для снижения нагрузки
        checkPauseAndDisableAutoStart()
        checkAutoStart()
        imgui.Process = SETTINGS.mainWindowState[0] and not STATE.gameMinimized

        if STATE.moveWidget then
            local cursorX, cursorY = getCursorPos()
            ini.widget.posX = cursorX
            ini.widget.posY = cursorY
            if isKeyJustPressed(0x20) then
                STATE.moveWidget = false
                sampToggleCursor(false)
                saveWindowSettings()
            end
        end

        if STATE.active or STATE.moveWidget then
            showInfoWindow()
        else
            showInfoWindowOff()
        end

        if not STATE.changingKey and isKeyJustPressed(STATE.keyBind) and not isSampfuncsConsoleActive() and
           not sampIsChatInputActive() and not sampIsDialogActive() and not isPauseMenuActive() then
            onToggleActive()
        end

        if STATE.active and STATE.floodCooldown < os.clock() * 1000 then
            local currentTime = os.clock() * 1000
            local interval = SETTINGS.useMilliseconds[0] and SETTINGS.otInterval[0] or (SETTINGS.otInterval[0] * 1000)
            if currentTime - STATE.lastOtTime >= interval then
                STATE.reportAttempts = STATE.reportAttempts + 1
                sampSendChat('/ot')
                logToFile("Отправка /ot, попытка #" .. STATE.reportAttempts)
                STATE.lastOtTime = currentTime
            end
        else
            STATE.startTime = os.clock()
        end
    end
end

-- Сброс ввода ImGui
function resetIO()
    local io = imgui.GetIO()
    for i = 0, 511 do io.KeysDown[i] = false end
    for i = 0, 4 do io.MouseDown[i] = false end
    io.KeyCtrl = false
    io.KeyShift = false
    io.KeyAlt = false
    io.KeySuper = false
end

-- Активация режима перемещения окна
function startMovingWindow()
    STATE.moveWidget = true
    showInfoWindow()
    sampToggleCursor(true)
    SETTINGS.mainWindowState[0] = false
    sampAddChatMessage(CONFIG.tagInfo .. '{FFFF00}Режим перемещения окна активирован. Нажмите "Пробел" для подтверждения.', -1)
end

-- Инициализация ImGui
imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    local iconRanges = new.ImWchar[3](faicons.min_range, faicons.max_range, 0)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(faicons.get_font_data_base85('solid'), 14, config, iconRanges)
    decor()
end)

-- Настройка стилей ImGui
function decor()
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    style.WindowPadding = imgui.ImVec2(12, 12)
    style.WindowRounding = 12.0
    style.ChildRounding = 10.0
    style.FramePadding = imgui.ImVec2(8, 6)
    style.FrameRounding = 10.0
    style.ItemSpacing = imgui.ImVec2(10, 10)
    style.ItemInnerSpacing = imgui.ImVec2(10, 10)
    style.ScrollbarSize = 12.0
    style.ScrollbarRounding = 10.0
    style.GrabRounding = 10.0
    style.PopupRounding = 10.0
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)
end

-- Обработка сообщений сервера
function sampev.onServerMessage(color, text)
    if text:find('%[(%W+)%] от (%w+_%w+)%[(%d+)%]:') and STATE.active then
        sampSendChat('/ot')
    end
    return filterFloodMessage(text)
end

-- Переключение состояния автоловли
function onToggleActive()
    STATE.active = not STATE.active
    STATE.manualDisable = not STATE.active
    SETTINGS.disableAutoStartOnToggle = not STATE.active
    local status = STATE.active and '{00FF00}включена' or '{FF0000}выключена'
    local statusArz = STATE.active and 'включена' or 'выключена'
    show_arz_notify('info', 'RepFlow', 'Ловля ' .. statusArz .. '!', 2000)
end

-- Сохранение настроек окна
function saveWindowSettings()
    ini.widget.posX = ini.widget.posX or 400
    ini.widget.posY = ini.widget.posY or 400
    inicfg.save(ini, CONFIG.iniFilename)
    sampAddChatMessage(CONFIG.tagInfo .. '{00FF00}Положение окна сохранено!', -1)
end

-- Обработка появления диалогов
function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    if dialogId == 1334 and SETTINGS.dialogHandlerEnabled[0] then
        STATE.lastDialogTime = os.clock()
        STATE.reportAnsweredCount = STATE.reportAnsweredCount + 1
        logToFile("Репорт принят, всего: " .. STATE.reportAnsweredCount)
        sampAddChatMessage(CONFIG.tag .. '{00FF00}Репорт принят! Отвечено: ' .. STATE.reportAnsweredCount, -1)
        if STATE.active then
            STATE.active = false
            show_arz_notify('info', 'RepFlow', 'Ловля отключена из-за окна репорта!', 3000)
        end
    end
end

-- Проверка автостарта ловли
function checkAutoStart()
    local currentTime = os.clock()
    if SETTINGS.autoStartEnabled[0] and not STATE.active and not STATE.gameMinimized and
       (STATE.afkExitTime == 0 or currentTime - STATE.afkExitTime >= CONFIG.afkCooldown) then
        if not SETTINGS.disableAutoStartOnToggle and (currentTime - STATE.lastDialogTime) > SETTINGS.dialogTimeout[0] then
            STATE.active = true
            show_arz_notify('info', 'RepFlow', 'Ловля включена по таймауту', 3000)
        end
    end
end

-- Сохранение общих настроек
function saveSettings()
    ini.main.dialogTimeout = SETTINGS.dialogTimeout[0]
    inicfg.save(ini, CONFIG.iniFilename)
end

-- Отрисовка ссылки
function imgui.Link(link, text)
    text = text or link
    local tSize = imgui.CalcTextSize(text)
    local p = imgui.GetCursorScreenPos()
    local DL = imgui.GetWindowDrawList()
    local col = { 0xFFFF7700, 0xFFFF9900 }
    if imgui.InvisibleButton('##' .. link, tSize) then os.execute('explorer ' .. link) end
    local color = imgui.IsItemHovered() and col[1] or col[2]
    DL:AddText(p, color, text)
    DL:AddLine(imgui.ImVec2(p.x, p.y + tSize.y), imgui.ImVec2(p.x + tSize.x, p.y + tSize.y), color)
end

-- Команда открытия меню
function cmd_arep(arg)
    SETTINGS.mainWindowState[0] = not SETTINGS.mainWindowState[0]
    imgui.Process = SETTINGS.mainWindowState[0]
end

-- Вкладка "Флудер"
function drawMainTab()
    local panelColor = COLORS.childPanel
    imgui.Text(faicons('gear') .. u8" Настройки  /  " .. faicons('message') .. u8" Флудер")
    imgui.Separator()
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("Flooder", imgui.ImVec2(0, 200), true) then
        imgui.PushItemWidth(100)
        if imgui.Checkbox(u8'Использовать миллисекунды', SETTINGS.useMilliseconds) then
            ini.main.useMilliseconds = SETTINGS.useMilliseconds[0]
            inicfg.save(ini, CONFIG.iniFilename)
        end
        imgui.PopItemWidth()
        imgui.Text(u8'Интервал отправки /ot (' .. (SETTINGS.useMilliseconds[0] and u8'мс' or u8'сек') .. '):')
        imgui.Text(u8'Текущий: ' .. SETTINGS.otInterval[0])
        imgui.PushItemWidth(45)
        imgui.InputText(u8'##otIntervalInput', SETTINGS.otIntervalBuffer, ffi.sizeof(SETTINGS.otIntervalBuffer))
        imgui.SameLine()
        if imgui.Button(faicons('floppy_disk') .. u8" Сохранить") then
            local newValue = tonumber(ffi.string(SETTINGS.otIntervalBuffer))
            if newValue then
                SETTINGS.otInterval[0] = newValue
                ini.main.otInterval = newValue
                inicfg.save(ini, CONFIG.iniFilename)
                sampAddChatMessage(CONFIG.tagInfo .. "Интервал сохранён: {32CD32}" .. newValue, -1)
            else
                sampAddChatMessage(CONFIG.tagInfo .. "Ошибка: {32CD32}Введите число.", -1)
            end
        end
        imgui.PopItemWidth()
        imgui.Text(u8'Пауза после флуда (сек):')
        imgui.Text(u8'Текущая: ' .. SETTINGS.floodPause[0])
        imgui.PushItemWidth(45)
        imgui.InputText(u8'##floodPauseInput', SETTINGS.floodPauseBuffer, ffi.sizeof(SETTINGS.floodPauseBuffer))
        imgui.SameLine()
        if imgui.Button(faicons('floppy_disk') .. u8" Сохранить паузу") then
            local newValue = tonumber(ffi.string(SETTINGS.floodPauseBuffer))
            if newValue and newValue >= 1 and newValue <= 60 then
                SETTINGS.floodPause[0] = newValue
                saveSettings()
                sampAddChatMessage(CONFIG.tagInfo .. "Пауза сохранена: {32CD32}" .. newValue .. " сек", -1)
            else
                sampAddChatMessage(CONFIG.tagInfo .. "Ошибка: {32CD32}1-60 сек.", -1)
            end
        end
        imgui.PopItemWidth()
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("InfoFlooder", imgui.ImVec2(0, 65), true) then
        imgui.Text(u8'Скрипт также ищет надпись в чате [Репорт] от Имя_Фамилия.')
        imgui.Text(u8'Флудер нужен для дополнительного способа ловли репорта.')
    end
    imgui.EndChild()
    imgui.PopStyleColor()
end

-- Вкладка "Настройки"
function drawSettingsTab()
    local panelColor = COLORS.childPanel
    imgui.Text(faicons('gear') .. u8" Настройки  /  " .. faicons('sliders') .. u8" Основные настройки")
    imgui.Separator()
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("KeyBind", imgui.ImVec2(0, 60), true) then
        imgui.Text(u8'Текущая клавиша активации:')
        imgui.SameLine()
        if imgui.Button(u8'' .. STATE.keyBindName) then
            STATE.changingKey = true
            show_arz_notify('info', 'RepFlow', 'Нажмите новую клавишу для активации', 2000)
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("DialogOptions", imgui.ImVec2(0, 150), true) then
        imgui.Text(u8"Обработка диалогов")
        if imgui.Checkbox(u8'Обрабатывать диалоги', SETTINGS.dialogHandlerEnabled) then
            ini.main.dialogHandlerEnabled = SETTINGS.dialogHandlerEnabled[0]
            inicfg.save(ini, CONFIG.iniFilename)
        end
        if imgui.Checkbox(u8'Автостарт ловли', SETTINGS.autoStartEnabled) then
            ini.main.autoStartEnabled = SETTINGS.autoStartEnabled[0]
            inicfg.save(ini, CONFIG.iniFilename)
        end
        if imgui.Checkbox(u8'Скрыть "Не флуди"', SETTINGS.hideFloodMsg) then
            ini.main.otklflud = SETTINGS.hideFloodMsg[0]
            inicfg.save(ini, CONFIG.iniFilename)
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("AutoStartTimeout", imgui.ImVec2(0, 100), true) then
        imgui.Text(u8'Тайм-аут автостарта (сек):')
        imgui.Text(u8'Текущий: ' .. SETTINGS.dialogTimeout[0])
        imgui.PushItemWidth(45)
        imgui.InputText(u8'', SETTINGS.dialogTimeoutBuffer, ffi.sizeof(SETTINGS.dialogTimeoutBuffer))
        imgui.SameLine()
        if imgui.Button(faicons('floppy_disk') .. u8" Сохранить") then
            local newValue = tonumber(ffi.string(SETTINGS.dialogTimeoutBuffer))
            if newValue and newValue >= 1 and newValue <= 9999 then
                SETTINGS.dialogTimeout[0] = newValue
                saveSettings()
                sampAddChatMessage(CONFIG.tagInfo .. "Тайм-аут сохранён: {32CD32}" .. newValue .. " сек", -1)
            else
                sampAddChatMessage(CONFIG.tagInfo .. "Ошибка: {32CD32}1-9999.", -1)
            end
        end
        imgui.PopItemWidth()
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("WindowPosition", imgui.ImVec2(0, 50), true) then
        imgui.Text(u8'Положение инфо-окна:')
        imgui.SameLine()
        if imgui.Button(u8'Изменить') then
            startMovingWindow()
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()
end

-- Фильтрация сообщений о флуде
function filterFloodMessage(text)
    if SETTINGS.hideFloodMsg[0] and text:find("%[Ошибка%] {FFFFFF}Не флуди!") then
        STATE.floodCooldown = os.clock() * 1000 + (SETTINGS.floodPause[0] * 1000)
        sampAddChatMessage(CONFIG.tag .. "Флуд, пауза на " .. SETTINGS.floodPause[0] .. " сек", -1)
        logToFile("Флуд, пауза на " .. SETTINGS.floodPause[0] .. " сек")
        return false
    elseif SETTINGS.hideFloodMsg[0] and text:find("%[Ошибка%] {FFFFFF}Сейчас нет вопросов в репорт!") then
        return false
    end
end

-- Проверка сворачивания игры
function checkPauseAndDisableAutoStart()
    if isPauseMenuActive() then
        if not STATE.gameMinimized then
            STATE.wasActiveBeforePause = STATE.active
            if STATE.active then STATE.active = false end
            STATE.gameMinimized = true
        end
    else
        if STATE.gameMinimized then
            STATE.gameMinimized = false
            STATE.afkExitTime = os.clock()
            if STATE.wasActiveBeforePause then
                sampAddChatMessage(CONFIG.tag .. '{FFFFFF}Вы вышли из паузы. Ловля отключена из-за AFK!', -1)
                logToFile("Выход из паузы, ловля отключена")
            end
        end
    end
end

-- Вкладка "Информация"
function drawInfoTab()
    local panelColor = COLORS.childPanel
    imgui.Text(faicons('star') .. u8" RepFlow  /  " .. faicons('circle_info') .. u8" Информация")
    imgui.Separator()
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("Author", imgui.ImVec2(0, 100), true) then
        imgui.Text(u8'Автор: Matthew_McLaren[18]')
        imgui.Text(u8'Версия: ' .. CONFIG.scriptVersion)
        imgui.Text(u8'Связь с разработчиком:')
        imgui.SameLine()
        imgui.Link('https://t.me/Zorahm', 'Telegram')
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("Info2", imgui.ImVec2(0, 100), true) then
        imgui.Text(u8'Скрипт автоматически отправляет команду /ot.')
        imgui.Text(u8'Через определенные интервалы времени.')
        imgui.Text(u8'А также выслеживает определенные надписи.')
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("Info3", imgui.ImVec2(0, 110), true) then
        imgui.CenterText(u8'А также спасибо:')
        imgui.Text(u8'Тестер: Carl_Mort[18].')
        imgui.Text(u8'Тестер: Sweet_Lemonte[18].')
        imgui.Text(u8'Тестер: Balenciaga_Collins[18].')
    end
    imgui.EndChild()

    if imgui.BeginChild("Stats", imgui.ImVec2(0, 100), true) then
        imgui.Text(u8'Статистика:')
        imgui.Text(u8'Попыток: ' .. STATE.reportAttempts)
        imgui.Text(u8'Принято: ' .. STATE.reportAnsweredCount)
        imgui.Text(u8'Пропущено: ' .. STATE.missedReports)
    end
    imgui.EndChild()

    imgui.PopStyleColor()
end

-- Вкладка "ChangeLog"
function drawChangeLogTab()
    imgui.Text(faicons('star') .. u8" RepFlow  /  " .. faicons('bolt') .. u8" ChangeLog")
    imgui.Separator()
    for _, entry in ipairs(changelogEntries) do
        if imgui.CollapsingHeader(u8("Версия ") .. entry.version) then
            imgui.Text(u8(entry.description))
        end
    end
end

-- Отрисовка главного окна
imgui.OnFrame(function() return SETTINGS.mainWindowState[0] end, function(player)
    imgui.SetNextWindowSize(imgui.ImVec2(800, 500), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.PushStyleColor(imgui.Col.WindowBg, COLORS.rightPanel)
    resetIO()

    if imgui.Begin(faicons('bolt') .. u8' RepFlow | Premium', SETTINGS.mainWindowState, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse) then
        imgui.PushStyleColor(imgui.Col.ChildBg, COLORS.leftPanel)
        if imgui.BeginChild("left_panel", imgui.ImVec2(130, -1), false) then
            local tabNames = { "Флудер", "Настройки", "Информация", "ChangeLog" }
            for i, name in ipairs(tabNames) do
                if i - 1 == SETTINGS.activeTab[0] then
                    imgui.PushStyleColor(imgui.Col.Button, COLORS.hover)
                else
                    imgui.PushStyleColor(imgui.Col.Button, COLORS.leftPanel)
                end
                imgui.PushStyleColor(imgui.Col.ButtonHovered, COLORS.hover)
                imgui.PushStyleColor(imgui.Col.ButtonActive, COLORS.hover)
                if imgui.Button(u8(name), imgui.ImVec2(125, 40)) then
                    SETTINGS.activeTab[0] = i - 1
                end
                imgui.PopStyleColor(3)
            end
        end
        imgui.EndChild()
        imgui.PopStyleColor()

        imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.ChildBg, COLORS.rightPanel)
        if imgui.BeginChild("right_panel", imgui.ImVec2(-1, 0), false) then
            if SETTINGS.activeTab[0] == 0 then drawMainTab()
            elseif SETTINGS.activeTab[0] == 1 then drawSettingsTab()
            elseif SETTINGS.activeTab[0] == 2 then drawInfoTab()
            elseif SETTINGS.activeTab[0] == 3 then drawChangeLogTab()
            end
        end
        imgui.EndChild()
        imgui.PopStyleColor()
    end
    imgui.End()
    imgui.PopStyleColor()
end)

-- Обработка смены клавиши
function onWindowMessage(msg, wparam, lparam)
    if STATE.changingKey then
        if msg == 0x100 or msg == 0x101 then
            STATE.keyBind = wparam
            STATE.keyBindName = vkeys.id_to_name(STATE.keyBind)
            STATE.changingKey = false
            ini.main.keyBind = string.format("0x%X", STATE.keyBind)
            ini.main.keyBindName = STATE.keyBindName
            inicfg.save(ini, CONFIG.iniFilename)
            sampAddChatMessage(string.format(CONFIG.tag .. '{FFFFFF}Новая клавиша: {00FF00}%s', STATE.keyBindName), -1)
            logToFile("Новая клавиша: " .. STATE.keyBindName)
            return false
        end
    end
end

-- Центрирование текста
function imgui.CenterText(text)
    local width = imgui.GetWindowWidth()
    local calc = imgui.CalcTextSize(text)
    imgui.SetCursorPosX(width / 2 - calc.x / 2)
    imgui.Text(text)
end

-- Уведомления Arizona RP
function show_arz_notify(type, title, text, time)
    if MONET_VERSION then
        local styleInt = type == 'info' and 3 or type == 'error' and 2 or 1
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, 62)
        raknetBitStreamWriteInt8(bs, 6)
        raknetBitStreamWriteBool(bs, true)
        raknetEmulPacketReceiveBitStream(220, bs)
        raknetDeleteBitStream(bs)
        sampAddChatMessage(CONFIG.tag .. "Уведомление: " .. text, -1)
    else
        local str = ('window.executeEvent(\'event.notify.initialize\', \'["%s", "%s", "%s", "%s"]\');'):format(type, title, text, time)
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, 17)
        raknetBitStreamWriteInt32(bs, 0)
        raknetBitStreamWriteInt32(bs, #str)
        raknetBitStreamWriteString(bs, str)
        raknetEmulPacketReceiveBitStream(220, bs)
        raknetDeleteBitStream(bs)
    end
end

-- Отрисовка информационного окна
imgui.OnFrame(function() return SETTINGS.infoWindowState[0] end, function(self)
    self.HideCursor = true
    imgui.SetNextWindowSize(imgui.ImVec2(220, 200), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(ini.widget.posX, ini.widget.posY), imgui.Cond.Always)
    imgui.Begin(faicons('star') .. u8" | Информация ", SETTINGS.infoWindowState, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
    imgui.CenterText(u8'Статус: ' .. (STATE.active and u8'Включена' or u8'Выключена'))
    local elapsedTime = os.clock() - STATE.startTime
    imgui.CenterText(string.format(u8'Время: %.2f сек', elapsedTime))
    imgui.CenterText(string.format(u8'Попыток: %d', STATE.reportAttempts))
    imgui.CenterText(string.format(u8'Принято: %d', STATE.reportAnsweredCount))
    imgui.Separator()
    imgui.Text(u8'Диалоги: ' .. (SETTINGS.dialogHandlerEnabled[0] and u8'Вкл' or u8'Выкл'))
    imgui.Text(u8'Автостарт: ' .. (SETTINGS.autoStartEnabled[0] and u8'Вкл' or u8'Выкл'))
    imgui.End()
end)

-- Управление видимостью информационного окна
function showInfoWindow()
    SETTINGS.infoWindowState[0] = true
end

function showInfoWindowOff()
    SETTINGS.infoWindowState[0] = false
end

-- Функция логирования:
function logToFile(message)
    local file = io.open(getWorkingDirectory() .. "/RepFlowLog.txt", "a")
    if file then
        file:write(os.date("[%H:%M:%S] ") .. message .. "\n")
        file:close()
    end
end
