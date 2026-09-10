# facts.example.ps1 - pryklad kontrolnyh faktiv bryfu.
# Copy to facts.ps1 and write the facts your sessions must know. facts.ps1 wins if both exist.
#
# Kozhen fakt - te, bez choho sesiya pratsiuvatyme hirshe.
# VAZHLYVO: patern musyt lovyty ZNACHENNIA, a ne zhadku temy.
#   pohano: "витрат"  - slovo trapliayetsia skriz, test "proide" i na porozhniomu znanni
#   dobre:  "42\s?%"  - konkretnyi fakt: abo v bryfi ye, abo nemaye
#
# UVAHA: UTF-8 z BOM. Identyfikatory - latynytseiu.

$Facts = @(
    @{ Name = "наступний крок сесії"; Rx = "З ЧОГО ПОЧАТИ" }
    @{ Name = "карта решти файлу";    Rx = "КАРТА СТАНУ" }
)
