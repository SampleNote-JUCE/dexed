if(NOT DEFINED MODULEINFO OR NOT EXISTS "${MODULEINFO}")
    message(FATAL_ERROR "moduleinfo.json not found: ${MODULEINFO}")
endif()

file(READ "${MODULEINFO}" content)
string(REGEX REPLACE
    "(\"Version\"[ \t\r\n]*:[ \t\r\n]*\")[^\"]*(\"[ \t\r\n]*,[ \t\r\n]*\"Factory Info\")"
    "\\1${VERSION}\\2"
    content "${content}")
file(WRITE "${MODULEINFO}" "${content}")