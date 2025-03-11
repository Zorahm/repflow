require 'lib.moonloader'
local imgui = require 'mimgui'
local sampev = require 'lib.samp.events'
local vkeys = require 'vkeys'
local encoding = require 'encoding'
local inicfg = require 'inicfg'
local ffi = require 'ffi'
local faicons = require 'fAwesome6'
local requests = require 'requests'
local dlstatus = require('moonloader').download_status

-- Конфигурация скрипта
local CONFIG = {
    iniFilename = 'RepFlowCFG.ini',
    scriptVersion = "3.6 | Premium",
    defaultKeyBind = 0x5A,
    defaultKeyBindName = 'Z',
    afkCooldown = 30,
    tag = "{1E90FF} [RepFlow]: {FFFFFF}",
    tagInfo = "{1E90FF} [Информация]: {FFFFFF}",
}

-- Утилиты ImGui
local new = imgui.new

-- Данные ChangeLog
local changelogEntries = {
    {
        version = "3.6 | Premium",
        description = "- Обновлено окно информации. Добавлены кликабельные ссылки на blast.hk и GitHub-репозиторий в меню 'Информация'.\n  - Исправлены потенциальные проблемы с сохранением настроек во вкладке 'Настройки'.\n -Улучшеная оптимизация скрипта. \n - Удалены CEF-уведомления Аризоны."
    },
    {
        version = "3.5 | Premium",
        description = "  - Добавлена кнопка сброса всех настроек в меню 'Настройки'.\n  - Теперь версия скрипта отображается в заголовке окна ImGui.\n  - Улучшена читаемость ChangeLog: добавлены отступы для пунктов.\n  - Оптимизирована производительность: минимизированы вызовы u8 в циклических функциях."
    },
    {
        version = "3.4 | Premium",
        description = "  - Обновлено меню настроек: чекбоксы распределены по категориям (Диалоги, Флуд, Обновления, Логирование).\n  - Добавлена возможность отключить логирование каждого действия (критические логи остаются).\n  - Добавлена поддержка профилей настроек: теперь можно сохранять и загружать до трёх профилей.\n  - Добавлено автоматическое логирование принятых репортов в файл repflow_reports.log.\n  - Добавлена новая вкладка 'Статистика' с информацией о времени работы, попытках, репортах и флуде.\n  - Добавлена команда /update для ручного запуска обновления скрипта (доступна после проверки обновлений)."
    },
}

-- Переменные для авто-обновлений
local update_state = false        -- Если true, начнётся обновление
local update_found = false        -- Если true, доступна команда /update
local script_vers = 3.6           -- Текущая версия скрипта (числовая)
local script_vers_text = "3.6"    -- Текущая версия для отображения пользователю

local update_url = "https://raw.githubusercontent.com/Zorahm/repflow/main/update.ini"
local update_path = getWorkingDirectory() .. "/update.ini"

local script_url = "https://raw.githubusercontent.com/Zorahm/repflow/main/!RepFlow.lua"
local script_path = thisScript().path

function check_update()
    downloadUrlToFile(update_url, update_path, function(id, status)
        if status == dlstatus.STATUS_ENDDOWNLOADDATA then
            local updateIni = inicfg.load(nil, update_path)
            if updateIni and updateIni.info and updateIni.info.vers then
                if tonumber(updateIni.info.vers) > script_vers then
                    sampAddChatMessage(CONFIG.tag .. "{FFFFFF}Имеется {32CD32}новая {FFFFFF}версия скрипта. Версия: {32CD32}" .. updateIni.info.vers_text .. ". {FFFFFF}Введите /update, чтобы обновить.", -1)
                    update_found = true -- Обновление найдено
                    logToFile("Найдена новая версия: " .. updateIni.info.vers_text)
                else
                    sampAddChatMessage(CONFIG.tag .. "{FFFFFF}У вас последняя версия скрипта: " .. script_vers_text, -1)
                    logToFile("Версия актуальна: " .. script_vers_text)
                end
            else
                sampAddChatMessage(CONFIG.tag .. "{FF0000}Ошибка: Не удалось загрузить информацию об обновлении.", -1)
                logToFile("Ошибка загрузки update.ini")
            end
            os.remove(update_path)
        elseif status == dlstatus.STATUS_DOWNLOADERROR then
            sampAddChatMessage(CONFIG.tag .. "{FF0000}Ошибка: Не удалось проверить обновления.", -1)
            logToFile("Ошибка проверки обновлений: download error")
        end
    end)
end

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
    reportAttempts = 0,
    floodCooldown = 0,
    scriptStartTime = os.clock(),
    floodCount = 0,
}

-- Настройки интерфейса и поведения
local SETTINGS = {
    otInterval = new.int(10),
    dialogTimeout = new.int(600),
    floodPause = new.int(10),
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
    selectedTheme = new.int(0),
    useFloodPause = new.bool(true),
    autoUpdateEnabled = new.bool(true),
    logActionsEnabled = new.bool(true),
    selectedProfile = new.int(0), -- Текущий выбранный профиль (0 = Профиль 1, 1 = Профиль 2, 2 = Профиль 3)
}

-- Предопределённые цветовые темы
local COLOR_THEMES = {
    {
        name = "Космос",
        leftPanel = imgui.ImVec4(10 / 255, 15 / 255, 30 / 255, 1.0),    -- Глубокий тёмно-синий
        rightPanel = imgui.ImVec4(15 / 255, 20 / 255, 40 / 255, 1.0),   -- Чуть светлее синий
        childPanel = imgui.ImVec4(5 / 255, 10 / 255, 25 / 255, 1.0),    -- Ещё темнее для контраста
        hover = imgui.ImVec4(50 / 255, 60 / 255, 100 / 255, 1.0),       -- Лёгкий голубой для акцента
        button = imgui.ImVec4(30 / 255, 40 / 255, 80 / 255, 1.0),       -- Цвет кнопок
        buttonHovered = imgui.ImVec4(50 / 255, 60 / 255, 100 / 255, 1.0), -- Цвет кнопок при наведении
        buttonActive = imgui.ImVec4(70 / 255, 80 / 255, 120 / 255, 1.0), -- Цвет кнопок при нажатии
        checkMark = imgui.ImVec4(150 / 255, 200 / 255, 255 / 255, 1.0), -- Цвет галочки в чекбоксе
        frameBg = imgui.ImVec4(20 / 255, 25 / 255, 50 / 255, 1.0),      -- Фон комбобокса и текстовых полей
        frameBgHovered = imgui.ImVec4(40 / 255, 45 / 255, 70 / 255, 1.0), -- Фон при наведении
        frameBgActive = imgui.ImVec4(60 / 255, 65 / 255, 90 / 255, 1.0), -- Фон при активации
        text = imgui.ImVec4(200 / 255, 220 / 255, 255 / 255, 1.0),      -- Цвет текста
    },
    {
        name = "Закат",
        leftPanel = imgui.ImVec4(50 / 255, 20 / 255, 10 / 255, 1.0),    -- Тёмный бордовый
        rightPanel = imgui.ImVec4(70 / 255, 30 / 255, 20 / 255, 1.0),   -- Тёплый красно-оранжевый
        childPanel = imgui.ImVec4(40 / 255, 15 / 255, 5 / 255, 1.0),    -- Глубокий тёмно-красный
        hover = imgui.ImVec4(120 / 255, 60 / 255, 40 / 255, 1.0),       -- Яркий оранжевый для выделения
        button = imgui.ImVec4(100 / 255, 40 / 255, 30 / 255, 1.0),      -- Цвет кнопок
        buttonHovered = imgui.ImVec4(120 / 255, 60 / 255, 40 / 255, 1.0), -- Цвет кнопок при наведении
        buttonActive = imgui.ImVec4(140 / 255, 80 / 255, 50 / 255, 1.0), -- Цвет кнопок при нажатии
        checkMark = imgui.ImVec4(255 / 255, 150 / 255, 100 / 255, 1.0), -- Цвет галочки в чекбоксе
        frameBg = imgui.ImVec4(80 / 255, 30 / 255, 20 / 255, 1.0),      -- Фон комбобокса и текстовых полей
        frameBgHovered = imgui.ImVec4(100 / 255, 50 / 255, 30 / 255, 1.0), -- Фон при наведении
        frameBgActive = imgui.ImVec4(120 / 255, 70 / 255, 40 / 255, 1.0), -- Фон при активации
        text = imgui.ImVec4(255 / 255, 200 / 255, 180 / 255, 1.0),      -- Цвет текста
    },
    {
        name = "Неон",
        leftPanel = imgui.ImVec4(20 / 255, 40 / 255, 20 / 255, 1.0),    -- Тёмный зелёный фон
        rightPanel = imgui.ImVec4(30 / 255, 50 / 255, 30 / 255, 1.0),   -- Чуть светлее зелёный
        childPanel = imgui.ImVec4(15 / 255, 30 / 255, 15 / 255, 1.0),   -- Контрастный тёмный
        hover = imgui.ImVec4(0 / 255, 200 / 255, 150 / 255, 1.0),       -- Яркий циан для кнопок
        button = imgui.ImVec4(40 / 255, 80 / 255, 40 / 255, 1.0),       -- Цвет кнопок
        buttonHovered = imgui.ImVec4(0 / 255, 200 / 255, 150 / 255, 1.0), -- Цвет кнопок при наведении
        buttonActive = imgui.ImVec4(0 / 255, 220 / 255, 170 / 255, 1.0), -- Цвет кнопок при нажатии
        checkMark = imgui.ImVec4(0 / 255, 255 / 255, 200 / 255, 1.0),   -- Цвет галочки в чекбоксе
        frameBg = imgui.ImVec4(30 / 255, 60 / 255, 30 / 255, 1.0),      -- Фон комбобокса и текстовых полей
        frameBgHovered = imgui.ImVec4(40 / 255, 80 / 255, 40 / 255, 1.0), -- Фон при наведении
        frameBgActive = imgui.ImVec4(50 / 255, 100 / 255, 50 / 255, 1.0), -- Фон при активации
        text = imgui.ImVec4(180 / 255, 255 / 255, 220 / 255, 1.0),      -- Цвет текста
    },
    {
        name = "Лаванда",
        leftPanel = imgui.ImVec4(40 / 255, 30 / 255, 60 / 255, 1.0),    -- Тёмный лавандовый
        rightPanel = imgui.ImVec4(50 / 255, 40 / 255, 80 / 255, 1.0),   -- Мягкий фиолетовый
        childPanel = imgui.ImVec4(30 / 255, 20 / 255, 50 / 255, 1.0),   -- Тёмный для панелей
        hover = imgui.ImVec4(100 / 255, 80 / 255, 140 / 255, 1.0),      -- Светлый лавандовый акцент
        button = imgui.ImVec4(60 / 255, 50 / 255, 100 / 255, 1.0),      -- Цвет кнопок
        buttonHovered = imgui.ImVec4(100 / 255, 80 / 255, 140 / 255, 1.0), -- Цвет кнопок при наведении
        buttonActive = imgui.ImVec4(120 / 255, 100 / 255, 160 / 255, 1.0), -- Цвет кнопок при нажатии
        checkMark = imgui.ImVec4(180 / 255, 150 / 255, 220 / 255, 1.0), -- Цвет галочки в чекбоксе
        frameBg = imgui.ImVec4(40 / 255, 30 / 255, 70 / 255, 1.0),      -- Фон комбобокса и текстовых полей
        frameBgHovered = imgui.ImVec4(60 / 255, 50 / 255, 90 / 255, 1.0), -- Фон при наведении
        frameBgActive = imgui.ImVec4(80 / 255, 70 / 255, 110 / 255, 1.0), -- Фон при активации
        text = imgui.ImVec4(220 / 255, 200 / 255, 255 / 255, 1.0),      -- Цвет текста
    },
    {
        name = "Графит",
        leftPanel = imgui.ImVec4(30 / 255, 30 / 255, 30 / 255, 1.0),    -- Тёмно-серый
        rightPanel = imgui.ImVec4(40 / 255, 40 / 255, 40 / 255, 1.0),   -- Средний серый
        childPanel = imgui.ImVec4(20 / 255, 20 / 255, 20 / 255, 1.0),   -- Очень тёмный серый
        hover = imgui.ImVec4(80 / 255, 80 / 255, 80 / 255, 1.0),        -- Светло-серый для кнопок
        button = imgui.ImVec4(50 / 255, 50 / 255, 50 / 255, 1.0),       -- Цвет кнопок
        buttonHovered = imgui.ImVec4(80 / 255, 80 / 255, 80 / 255, 1.0), -- Цвет кнопок при наведении
        buttonActive = imgui.ImVec4(100 / 255, 100 / 255, 100 / 255, 1.0), -- Цвет кнопок при нажатии
        checkMark = imgui.ImVec4(180 / 255, 180 / 255, 180 / 255, 1.0), -- Цвет галочки в чекбоксе
        frameBg = imgui.ImVec4(30 / 255, 30 / 255, 30 / 255, 1.0),      -- Фон комбобокса и текстовых полей
        frameBgHovered = imgui.ImVec4(50 / 255, 50 / 255, 50 / 255, 1.0), -- Фон при наведении
        frameBgActive = imgui.ImVec4(70 / 255, 70 / 255, 70 / 255, 1.0), -- Фон при активации
        text = imgui.ImVec4(200 / 255, 200 / 255, 200 / 255, 1.0),      -- Цвет текста
    },
}

-- Текущая цветовая схема (по умолчанию - первая тема)
local COLORS = COLOR_THEMES[1]

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
        selectedTheme = 0,
        useFloodPause = true,
        autoUpdateEnabled = true,
        logActionsEnabled = true,
        selectedProfile = 0, -- По умолчанию Профиль 1
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
SETTINGS.useMilliseconds[0] = ini.main.useMilliseconds == true
SETTINGS.dialogTimeout[0] = tonumber(ini.main.dialogTimeout) or 600
SETTINGS.floodPause[0] = tonumber(ini.main.floodPause) or 10
SETTINGS.dialogHandlerEnabled[0] = ini.main.dialogHandlerEnabled == true
SETTINGS.autoStartEnabled[0] = ini.main.autoStartEnabled == true
SETTINGS.hideFloodMsg[0] = ini.main.otklflud == true
SETTINGS.selectedTheme[0] = tonumber(ini.main.selectedTheme) or 0
COLORS = COLOR_THEMES[SETTINGS.selectedTheme[0] + 1] -- Применяем загруженную тему
SETTINGS.useFloodPause[0] = ini.main.useFloodPause == true
SETTINGS.autoUpdateEnabled[0] = ini.main.autoUpdateEnabled == true
SETTINGS.logActionsEnabled[0] = ini.main.logActionsEnabled == true
SETTINGS.selectedProfile[0] = ini.main.selectedProfile or 0

-- Основной цикл скрипта
function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end
    sampRegisterChatCommand("arep", cmd_arep)
    sampRegisterChatCommand("update", cmd_update)
    sampAddChatMessage(CONFIG.tag .. 'Скрипт {00FF00}загружен.{FFFFFF} Активация меню: {00FF00}/arep', -1)
    logToFile("Скрипт загружен")

    -- Загружаем настройки из выбранного профиля
    loadSettingsFromProfile()

    -- Проверка обновлений при запуске, если включено
    if SETTINGS.autoUpdateEnabled[0] then
        sampAddChatMessage(CONFIG.tag .. "Проверка обновлений...", -1)
        check_update()
    else
        sampAddChatMessage(CONFIG.tag .. "Автоматическая проверка обновлений отключена", -1)
    end

    local lastMoveCheck = 0 -- Для проверки нажатия пробела
    local moveCheckInterval = 50 -- Проверяем пробел раз в 50 мс

    while true do
        wait(0) -- Уменьшаем wait для более плавного обновления
        checkPauseAndDisableAutoStart()
        checkAutoStart()
        imgui.Process = SETTINGS.mainWindowState[0] and not STATE.gameMinimized

        if update_state then
            downloadUrlToFile(script_url, script_path, function(id, status)
                if status == dlstatus.STATUS_ENDDOWNLOADDATA then
                    sampAddChatMessage(CONFIG.tag .. "{FFFFFF}Скрипт {32CD32}успешно {FFFFFF}обновлён. Перезапустите MoonLoader.", -1)
                    logToFile("Скрипт успешно обновлён")
                    thisScript():reload()
                elseif status == dlstatus.STATUS_DOWNLOADERROR then
                    sampAddChatMessage(CONFIG.tag .. "{FF0000}Ошибка: Не удалось скачать обновление.", -1)
                    logToFile("Ошибка при скачивании обновления")
                end
            end)
            break
        end

        if STATE.moveWidget then
            local cursorX, cursorY = getCursorPos()
            ini.widget.posX = cursorX
            ini.widget.posY = cursorY
            local currentTime = os.clock() * 1000
            if currentTime - lastMoveCheck >= moveCheckInterval then
                if isKeyJustPressed(0x20) then
                    STATE.moveWidget = false
                    sampToggleCursor(false)
                    saveWindowSettings()
                end
                lastMoveCheck = currentTime
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
    logToFile("Ловля " .. statusArz)
end

-- Сохранение настроек окна
function saveWindowSettings()
    ini.widget.posX = ini.widget.posX or 400
    ini.widget.posY = ini.widget.posY or 400
    inicfg.save(ini, CONFIG.iniFilename)
    sampAddChatMessage(CONFIG.tagInfo .. '{00FF00}Положение окна сохранено!', -1)
end

-- Обработка появления диалогов
function onShowDialog(dialogId, style, title, button1, button2, text)
    if SETTINGS.dialogHandlerEnabled[0] and dialogId == 1334 and title:find("Жалоба от") then
        local playerName = text:match("Жалоба:")
        local reportText = text:match(":(.+)%[Принять%]")
        if playerName and reportText then
            logReport(playerName, reportText)
            STATE.reportAnsweredCount = STATE.reportAnsweredCount + 1
            sampSendDialogResponse(dialogId, 1, 0, "")
            sampAddChatMessage(CONFIG.tag .. "Репорт принят от " .. playerName, -1)
            logToFile("Репорт принят от " .. playerName)
            return false
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
            sampAddChatMessage(CONFIG.tag .. "Ловля включена по тайм-ауту", -1)
            logToFile("Ловля включена по таймауту")
        end
    end
end

-- Сохранение общих настроек
function saveSettings()
    ini.main.otInterval = SETTINGS.otInterval[0]
    ini.main.dialogTimeout = SETTINGS.dialogTimeout[0]
    ini.main.floodPause = SETTINGS.floodPause[0]
    ini.main.useMilliseconds = SETTINGS.useMilliseconds[0] == true -- Преобразуем в true/false
    ini.main.dialogHandlerEnabled = SETTINGS.dialogHandlerEnabled[0] == true
    ini.main.autoStartEnabled = SETTINGS.autoStartEnabled[0] == true
    ini.main.otklflud = SETTINGS.hideFloodMsg[0] == true
    ini.main.selectedTheme = SETTINGS.selectedTheme[0]
    ini.main.useFloodPause = SETTINGS.useFloodPause[0] == true
    ini.main.autoUpdateEnabled = SETTINGS.autoUpdateEnabled[0] == true
    ini.main.logActionsEnabled = SETTINGS.logActionsEnabled[0] == true
    ini.main.selectedProfile = SETTINGS.selectedProfile[0]
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

function cmd_update(arg)
    if update_found then
        update_state = true
        sampAddChatMessage(CONFIG.tag .. "Начинается обновление...", -1)
        logToFile("Пользователь запустил обновление")
    else
        sampAddChatMessage(CONFIG.tag .. "{FF0000}Нет доступных обновлений для установки.", -1)
    end
end

-- Вкладка "Флудер"
function drawMainTab()
    local panelColor = COLORS.childPanel
    imgui.Text(faicons('gear') .. u8" Настройки  /  " .. faicons('message') .. u8" Флудер")
    imgui.Separator()
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("Flooder", imgui.ImVec2(0, 150), true) then
        imgui.PushItemWidth(100)
        if imgui.Checkbox(u8'Использовать миллисекунды', SETTINGS.useMilliseconds) then
            ini.main.useMilliseconds = SETTINGS.useMilliseconds[0]
            saveSettings() -- Сохраняем все настройки
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
                saveSettings() -- Сохраняем все настройки
                sampAddChatMessage(CONFIG.tagInfo .. "Интервал сохранён: {32CD32}" .. newValue, -1)
            else
                sampAddChatMessage(CONFIG.tagInfo .. "Ошибка: {32CD32}Введите число.", -1)
            end
        end
        imgui.PopItemWidth()
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("FloodPause", imgui.ImVec2(0, 100), true) then
        imgui.Text(u8'Пауза после флуда (сек):')
        imgui.Text(u8'Текущая: ' .. SETTINGS.floodPause[0])
        imgui.PushItemWidth(45)
        imgui.InputText(u8'##floodPauseInput', SETTINGS.floodPauseBuffer, ffi.sizeof(SETTINGS.floodPauseBuffer))
        imgui.SameLine()
        if imgui.Button(faicons('floppy_disk') .. u8" Сохранить паузу") then
            local newValue = tonumber(ffi.string(SETTINGS.floodPauseBuffer))
            if newValue and newValue >= 1 and newValue <= 60 then
                SETTINGS.floodPause[0] = newValue
                saveSettings() -- Сохраняем все настройки
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
            sampAddChatMessage(CONFIG.tag .. "Нажмите новую клавишу активации", -1)
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("DialogOptions", imgui.ImVec2(0, 110), true) then
        imgui.Text(u8"Обработка диалогов")
        if imgui.Checkbox(u8'Обрабатывать диалоги', SETTINGS.dialogHandlerEnabled) then
            saveSettings() -- Сохраняем все настройки
        end
        if imgui.Checkbox(u8'Автостарт ловли', SETTINGS.autoStartEnabled) then
            saveSettings() -- Сохраняем все настройки
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("FloodOptions", imgui.ImVec2(0, 110), true) then
        imgui.Text(u8"Настройки флуда")
        if imgui.Checkbox(u8'Скрыть "Не флуди"', SETTINGS.hideFloodMsg) then
            saveSettings() -- Сохраняем все настройки
        end
        if imgui.Checkbox(u8'Использовать паузу после флуда', SETTINGS.useFloodPause) then
            saveSettings() -- Сохраняем все настройки
            sampAddChatMessage(CONFIG.tagInfo .. "Пауза после флуда: {32CD32}" .. (SETTINGS.useFloodPause[0] and "включена" or "выключена"), -1)
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("UpdateOptions", imgui.ImVec2(0, 110), true) then
        imgui.Text(u8"Обновления")
        if imgui.Checkbox(u8'Автообновление при запуске', SETTINGS.autoUpdateEnabled) then
            saveSettings() -- Сохраняем все настройки
            sampAddChatMessage(CONFIG.tagInfo .. "Автообновление: {32CD32}" .. (SETTINGS.autoUpdateEnabled[0] and "включено" or "выключено"), -1)
        end
        imgui.Text(u8'Ручная проверка:')
        imgui.SameLine()
        if imgui.Button(u8'Проверить') then
            sampAddChatMessage(CONFIG.tag .. "Проверка обновлений...", -1)
            check_update()
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("LoggingOptions", imgui.ImVec2(0, 80), true) then
        imgui.Text(u8"Логирование")
        if imgui.Checkbox(u8'Логировать действия', SETTINGS.logActionsEnabled) then
            saveSettings() -- Сохраняем все настройки
            sampAddChatMessage(CONFIG.tagInfo .. "Логирование действий: {32CD32}" .. (SETTINGS.logActionsEnabled[0] and "включено" or "выключено"), -1)
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("AutoStartTimeout", imgui.ImVec2(0, 100), true) then
        imgui.Text(u8'Тайм-аут автостарта (сек):')
        imgui.Text(u8'Текущий: ' .. SETTINGS.dialogTimeout[0])
        imgui.PushItemWidth(45)
        imgui.InputText(u8'##dialogTimeoutInput', SETTINGS.dialogTimeoutBuffer, ffi.sizeof(SETTINGS.dialogTimeoutBuffer))
        imgui.SameLine()
        if imgui.Button(faicons('floppy_disk') .. u8" Сохранить") then
            local newValue = tonumber(ffi.string(SETTINGS.dialogTimeoutBuffer))
            if newValue and newValue >= 1 and newValue <= 9999 then
                SETTINGS.dialogTimeout[0] = newValue
                saveSettings() -- Сохраняем все настройки
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
    if imgui.BeginChild("WindowPosition", imgui.ImVec2(0, 60), true) then
        imgui.Text(u8'Положение инфо-окна:')
        imgui.SameLine()
        if imgui.Button(u8'Изменить') then
            startMovingWindow()
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("ProfileOptions", imgui.ImVec2(0, 90), true) then
        imgui.Text(u8'Профиль настроек:')
        local profiles = { u8"Профиль 1", u8"Профиль 2", u8"Профиль 3" }
        local cProfiles = ffi.new("const char*[?]", #profiles)
        for i, name in ipairs(profiles) do cProfiles[i - 1] = name end
        if imgui.Combo(u8'##ProfileSelector', SETTINGS.selectedProfile, cProfiles, #profiles) then
            ini.main.selectedProfile = SETTINGS.selectedProfile[0]
            saveSettings() -- Сохраняем все настройки
            loadSettingsFromProfile()
        end
        imgui.SameLine()
        if imgui.Button(u8'Сохранить профиль') then
            local profileName = "profile_" .. (SETTINGS.selectedProfile[0] + 1)
            inicfg.save(ini, "moonloader/" .. profileName .. ".ini")
            saveSettings() -- Сохраняем все настройки
            sampAddChatMessage(CONFIG.tag .. "Профиль сохранён: Профиль " .. (SETTINGS.selectedProfile[0] + 1), -1)
            logToFile("Профиль сохранён: Профиль " .. (SETTINGS.selectedProfile[0] + 1))
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("ColorScheme", imgui.ImVec2(0, 100), true) then
        imgui.Text(u8'Цветовая схема:')
        local themeNames = {}
        for i, theme in ipairs(COLOR_THEMES) do
            themeNames[i] = u8(theme.name)
        end
        local cThemeNames = ffi.new("const char*[?]", #themeNames)
        for i, name in ipairs(themeNames) do
            cThemeNames[i - 1] = name
        end
        if imgui.Combo(u8'##ThemeSelector', SETTINGS.selectedTheme, cThemeNames, #themeNames) then
            COLORS = COLOR_THEMES[SETTINGS.selectedTheme[0] + 1]
            saveSettings() -- Сохраняем все настройки
            sampAddChatMessage(CONFIG.tagInfo .. "Тема изменена: {32CD32}" .. COLOR_THEMES[SETTINGS.selectedTheme[0] + 1].name, -1)
            logToFile("Тема изменена на: " .. COLOR_THEMES[SETTINGS.selectedTheme[0] + 1].name)
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()
end

function logReport(playerName, reportText)
    local reportFile = io.open("moonloader/repflow_reports.log", "a")
    if reportFile then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        reportFile:write(string.format("[%s] Игрок: %s | Репорт: %s\n", timestamp, playerName, reportText))
        reportFile:close()
    end
end

function filterFloodMessage(text)
    if SETTINGS.hideFloodMsg[0] and text:find("%[Ошибка%] {FFFFFF}Не флуди!") then
        STATE.floodCount = STATE.floodCount + 1
        if SETTINGS.useFloodPause[0] then
            STATE.floodCooldown = os.clock() * 1000 + (SETTINGS.floodPause[0] * 1000)
            sampAddChatMessage(CONFIG.tag .. "Флуд, пауза на " .. SETTINGS.floodPause[0] .. " сек", -1)
            logToFile("Флуд, пауза на " .. SETTINGS.floodPause[0] .. " сек")
        else
            sampAddChatMessage(CONFIG.tag .. "Флуд обнаружен, пауза отключена", -1)
            logToFile("Флуд обнаружен, пауза отключена")
        end
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
    imgui.Text(faicons('star') .. u8" RepFlow  /  " .. faicons('user') .. u8" Информация")
    imgui.Separator()
    local panelColor = COLORS.childPanel
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("Info", imgui.ImVec2(0, 400), true) then
        imgui.Text(u8"RepFlow v" .. CONFIG.scriptVersion .. " by Matthew_McLaren[18]")
        imgui.Text(u8"Скрипт для автоматической ловли репортов на серверах Arizona RP.")
        imgui.Separator()
        imgui.Text(u8"Основные функции:")
        imgui.TextWrapped(u8"- Автоматическая отправка команды /ot с настраиваемым интервалом.")
        imgui.TextWrapped(u8"- Обнаружение репортов в чате по ключевой фразе '[Репорт] от Имя_Фамилия'.")
        imgui.TextWrapped(u8"- Автоматическая обработка диалога 1334 для принятия репортов.")
        imgui.TextWrapped(u8"- Статистика: попытки, принятые репорты, флуды.")
        imgui.TextWrapped(u8"- Поддержка профилей настроек и цветовых тем.")
        imgui.Separator()
        imgui.Text(u8"Ссылки:")
        imgui.Link(u8"https://blast.hk/threads/12345", u8"Тема на blast.hk")
        imgui.Link(u8"https://github.com/Zorahm/RepFlow", u8"GitHub-репозиторий")
        imgui.Separator()
        imgui.Text(u8"Благодарности:")
        imgui.Text(u8"Тестеры: Carl_Mort[18], Sweet_Lemonte[18], Balenciaga_Collins[18].")
        imgui.Text(u8"Связь с автором: Telegram @Zorahm")
    end
    imgui.EndChild()
    imgui.PopStyleColor()
end

function drawStatsTab()
    local panelColor = COLORS.childPanel
    imgui.Text(faicons('star') .. u8" RepFlow  /  " .. faicons('user') .. u8" Статистика")
    imgui.Separator()
    imgui.PushStyleColor(imgui.Col.ChildBg, panelColor)
    if imgui.BeginChild("Stats", imgui.ImVec2(0, -1), true) then
        imgui.Text(u8"Общее время работы: " .. string.format("%.2f", os.clock() - STATE.scriptStartTime) .. u8" сек")
        imgui.Text(u8"Попыток отправки /ot: " .. STATE.reportAttempts)
        imgui.Text(u8"Принято репортов: " .. STATE.reportAnsweredCount)
        imgui.Text(u8"Обнаружено флудов: " .. STATE.floodCount)
        if imgui.Button(u8"Сбросить статистику") then
            STATE.reportAttempts = 0
            STATE.reportAnsweredCount = 0
            STATE.floodCount = 0
            STATE.scriptStartTime = os.clock()
            sampAddChatMessage(CONFIG.tag .. "Статистика сброшена", -1)
            logToFile("Статистика сброшена")
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()
end

-- Вкладка "ChangeLog"
function drawChangeLogTab()
    imgui.Text(faicons('star') .. u8" RepFlow  /  " .. faicons('bolt') .. u8" ChangeLog. Полный смотрите на GitHub!")
    imgui.Separator()
    for _, entry in ipairs(changelogEntries) do
        if imgui.CollapsingHeader(u8("Версия ") .. entry.version) then
            imgui.PushTextWrapPos(imgui.GetWindowWidth() - 20)
            imgui.TextWrapped(u8(entry.description))
            imgui.PopTextWrapPos()
        end
    end
end

-- Отрисовка главного окна
imgui.OnFrame(function() return SETTINGS.mainWindowState[0] end, function(player)
    imgui.SetNextWindowSize(imgui.ImVec2(800, 500), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    -- Применяем стили для всех элементов
    imgui.PushStyleColor(imgui.Col.WindowBg, COLORS.rightPanel)
    imgui.PushStyleColor(imgui.Col.Text, COLORS.text)
    imgui.PushStyleColor(imgui.Col.Button, COLORS.button)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, COLORS.buttonHovered)
    imgui.PushStyleColor(imgui.Col.ButtonActive, COLORS.buttonActive)
    imgui.PushStyleColor(imgui.Col.CheckMark, COLORS.checkMark)
    imgui.PushStyleColor(imgui.Col.FrameBg, COLORS.frameBg)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, COLORS.frameBgHovered)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, COLORS.frameBgActive)
    resetIO()

    if imgui.Begin(faicons('bolt') .. u8' RepFlow | Premium', SETTINGS.mainWindowState, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse) then
        imgui.PushStyleColor(imgui.Col.ChildBg, COLORS.leftPanel)
        if imgui.BeginChild("left_panel", imgui.ImVec2(125, -1), false) then
            local tabNames = { "Флудер", "Настройки", "Информация", "Статистика", "ChangeLog" }
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
            elseif SETTINGS.activeTab[0] == 3 then drawStatsTab()
            elseif SETTINGS.activeTab[0] == 4 then drawChangeLogTab()
            end
        end
        imgui.EndChild()
        imgui.PopStyleColor()
    end
    imgui.End()
    -- Убираем все стили
    imgui.PopStyleColor(9) -- Соответствует количеству PushStyleColor
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
function loadSettingsFromProfile()
    local profileName = "profile_" .. (SETTINGS.selectedProfile[0] + 1)
    local profileIni = inicfg.load(defaultConfig, "moonloader/" .. profileName .. ".ini")
    SETTINGS.otInterval[0] = profileIni.main.otInterval or 10
    SETTINGS.dialogTimeout[0] = profileIni.main.dialogTimeout or 600
    SETTINGS.floodPause[0] = profileIni.main.floodPause or 10
    SETTINGS.useMilliseconds[0] = profileIni.main.useMilliseconds == true -- Загружаем как булево
    SETTINGS.hideFloodMsg[0] = profileIni.main.otklflud == true
    SETTINGS.autoStartEnabled[0] = profileIni.main.autoStartEnabled == true
    SETTINGS.dialogHandlerEnabled[0] = profileIni.main.dialogHandlerEnabled == true
    SETTINGS.selectedTheme[0] = profileIni.main.selectedTheme or 0
    SETTINGS.useFloodPause[0] = profileIni.main.useFloodPause == true
    SETTINGS.autoUpdateEnabled[0] = profileIni.main.autoUpdateEnabled == true
    SETTINGS.logActionsEnabled[0] = profileIni.main.logActionsEnabled == true
    COLORS = COLOR_THEMES[SETTINGS.selectedTheme[0] + 1]
    ini.widget.posX = profileIni.widget.posX or 400
    ini.widget.posY = profileIni.widget.posY or 400

    -- Синхронизируем ini.main с текущими настройками профиля
    ini.main = profileIni.main or {}
    ini.main.otInterval = SETTINGS.otInterval[0]
    ini.main.dialogTimeout = SETTINGS.dialogTimeout[0]
    ini.main.floodPause = SETTINGS.floodPause[0]
    ini.main.useMilliseconds = SETTINGS.useMilliseconds[0]
    ini.main.dialogHandlerEnabled = SETTINGS.dialogHandlerEnabled[0]
    ini.main.autoStartEnabled = SETTINGS.autoStartEnabled[0]
    ini.main.otklflud = SETTINGS.hideFloodMsg[0]
    ini.main.selectedTheme = SETTINGS.selectedTheme[0]
    ini.main.useFloodPause = SETTINGS.useFloodPause[0]
    ini.main.autoUpdateEnabled = SETTINGS.autoUpdateEnabled[0]
    ini.main.logActionsEnabled = SETTINGS.logActionsEnabled[0]
    ini.main.selectedProfile = SETTINGS.selectedProfile[0]

    inicfg.save(ini, CONFIG.iniFilename) -- Сохраняем обновлённые настройки
    sampAddChatMessage(CONFIG.tag .. "Загружен профиль: Профиль " .. (SETTINGS.selectedProfile[0] + 1), -1)
    logToFile("Загружен профиль: Профиль " .. (SETTINGS.selectedProfile[0] + 1))
end

-- Отрисовка информационного окна
imgui.OnFrame(function() return SETTINGS.infoWindowState[0] end, function(self)
    self.HideCursor = true
    imgui.SetNextWindowSize(imgui.ImVec2(220, 200), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(ini.widget.posX, ini.widget.posY), imgui.Cond.Always)
    imgui.Begin(faicons('star') .. u8" | Информация ", SETTINGS.infoWindowState, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
    imgui.CenterText(u8'Статус: ' .. (STATE.active and u8'Включена' or u8'Выключена'))
    local elapsedTime = os.clock() - STATE.startTime
    imgui.Text(string.format(u8'Время: %.2f сек', elapsedTime))
    imgui.Text(string.format(u8'Попыток: %d', STATE.reportAttempts))
    imgui.Text(string.format(u8'Принято: %d', STATE.reportAnsweredCount))
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

-- Функция логирования
function logToFile(message)
    if not SETTINGS.logActionsEnabled[0] and not message:find("Ошибка") then
        return -- Не логируем, если отключено, кроме ошибок
    end
    local logFile = io.open("moonloader/repflow.log", "a")
    if logFile then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        logFile:write(string.format("[%s] %s\n", timestamp, message))
        logFile:close()
    end
end
