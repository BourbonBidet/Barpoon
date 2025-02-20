function! barpoon#barbar#bar#on_click_pin_handler(minwid, _clicks, _btn, _modifiers) abort
  call luaeval("require'barpoon.barbar.bar'.on_click_pin_handler(_A)", a:minwid)
endfunction

