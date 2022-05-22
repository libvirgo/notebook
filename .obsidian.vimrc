set clipboard=unnamed
exmap back obcommand app:go-back
nmap [b :back
exmap forward obcommand app:go-forward
nmap ]b :forward
exmap follow obcommand editor:follow-link
nmap K :follow
exmap vertical obcommand workspace:split-vertical
nmap f\ :vertical
exmap horizontal obcommand workspace:split-horizontal
nmap f- :horizontal
exmap close obcommand workspace:close
nmap fc :close
exmap close-others obcommand workspace:close-others
nmap f1 :close-others
exmap focus_top obcommand editor:focus-top
nmap fk :focus_top
exmap focus_right obcommand editor:focus-right
nmap fl :focus_right
exmap focus_left obcommand editor:focus-left
nmap fh :focus_left
exmap focus_bottom obcommand editor:focus-bottom
nmap fj :focus_bottom



