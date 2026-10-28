gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

local font = resource.load_font "font.ttf"
local logo = resource.load_image "logo.png"

-- Couleurs E.Leclerc (approximatives)
local BLEU   = {0.00, 0.36, 0.67}
local ORANGE = {0.97, 0.58, 0.12}
local ROUGE  = {0.85, 0.10, 0.10}
local BLANC  = {1, 1, 1}

local tex_blanc   = resource.create_colored_texture(1, 1, 1, 1)
local tex_orange  = resource.create_colored_texture(ORANGE[1], ORANGE[2], ORANGE[3], 1)
local tex_bleu    = resource.create_colored_texture(BLEU[1], BLEU[2], BLEU[3], 1)
local tex_rouge   = resource.create_colored_texture(ROUGE[1], ROUGE[2], ROUGE[3], 1)
local tex_bandeau = resource.create_colored_texture(0, 0, 0, 0.25)   -- assombrit le fond derriere la date

-- Disque ou anneau lisse, dessine par un shader (pas d'image necessaire)
local shader_disque = resource.create_shader[[
  #ifdef GL_ES
  precision mediump float;
  #endif
  uniform sampler2D Texture;
  varying vec2 TexCoord;
  uniform float interieur;
  uniform float flou;
  uniform float r, g, b;
  void main() {
    float d = length(TexCoord - vec2(0.5)) * 2.0;
    float a = (1.0 - smoothstep(1.0 - flou, 1.0, d)) * smoothstep(interieur - flou, interieur, d);
    gl_FragColor = texture2D(Texture, TexCoord) * vec4(r, g, b, a);
  }
]]

local JOURS = {"DIMANCHE","LUNDI","MARDI","MERCREDI","JEUDI","VENDREDI","SAMEDI"}
local MOIS  = {"JANVIER","FÉVRIER","MARS","AVRIL","MAI","JUIN","JUILLET",
               "AOÛT","SEPTEMBRE","OCTOBRE","NOVEMBRE","DÉCEMBRE"}

-- Reglages (modifiables depuis le tableau de bord info-beamer)
local trotteuse = true

util.json_watch("config.json", function(config)
  if config.trotteuse ~= nil then trotteuse = config.trotteuse end
end)

-- Heure d'été européenne automatique (France)
local function jour_semaine(y, m, d)   -- 0 = dimanche
  local t = {0,3,2,5,0,3,5,2,6,4,2,4}
  if m < 3 then y = y - 1 end
  return (y + math.floor(y/4) - math.floor(y/100) + math.floor(y/400) + t[m] + d) % 7
end

local function decalage(utc)
  local debut = 3 * 10000 + (31 - jour_semaine(utc.year, 3, 31)) * 100 + 1
  local fin   = 10 * 10000 + (31 - jour_semaine(utc.year, 10, 31)) * 100 + 1
  local now   = utc.month * 10000 + utc.day * 100 + utc.hour
  if now >= debut and now < fin then return 7200 end
  return 3600
end

local function disque(cx, cy, rayon, c, interieur)
  shader_disque:use{
    interieur = interieur or 0,
    flou = 1.5 / rayon,
    r = c[1], g = c[2], b = c[3],
  }
  tex_blanc:draw(cx - rayon, cy - rayon, cx + rayon, cy + rayon)
  shader_disque:deactivate()
end

-- Rectangle tourne autour du centre du cadran (angle en degres, 0 = midi)
-- de "debut" a "fin" le long du rayon (negatif = cote oppose)
local function trait(cx, cy, angle, debut, fin, largeur, tex)
  gl.pushMatrix()
  gl.translate(cx, cy)
  gl.rotate(angle, 0, 0, 1)
  tex:draw(-largeur / 2, -fin, largeur / 2, -debut)
  gl.popMatrix()
end

local function centre(texte, x, y, taille, c)
  local w = font:width(texte, taille)
  font:write(x - w / 2, y - taille / 2, texte, taille, c[1], c[2], c[3], 1)
end

local function cadran(cx, cy, R)
  -- Lunette orange, face blanche
  disque(cx, cy, R, ORANGE)
  disque(cx, cy, R * 0.95, BLANC)

  -- Graduations : minutes fines, heures epaisses
  for i = 0, 59 do
    if i % 5 == 0 then
      trait(cx, cy, i * 6, R * 0.80, R * 0.91, R * 0.022, tex_bleu)
    else
      trait(cx, cy, i * 6, R * 0.87, R * 0.91, R * 0.007, tex_bleu)
    end
  end

  for h = 1, 12 do
    local a = math.rad(h * 30)
    centre(tostring(h), cx + math.sin(a) * R * 0.68, cy - math.cos(a) * R * 0.68,
           R * 0.15, BLEU)
  end
end

local function logo_cadran(cx, cy, R)
  local iw, ih = logo:size()
  local lw = R * 0.80
  local lh = lw * ih / iw
  local y  = cy - R * 0.36 - lh / 2
  logo:draw(cx - lw / 2, y, cx + lw / 2, y + lh)
end

-- Aiguille aux deux bouts arrondis
local function aiguille(cx, cy, angle, debut, fin, largeur, tex, c)
  trait(cx, cy, angle, debut, fin, largeur, tex)
  local a = math.rad(angle)
  local sx, sy = math.sin(a), -math.cos(a)
  disque(cx + sx * fin,   cy + sy * fin,   largeur / 2, c)
  disque(cx + sx * debut, cy + sy * debut, largeur / 2, c)
end

local function aiguilles(cx, cy, R, d)
  local m = d.min + d.sec / 60
  local h = (d.hour % 12) + m / 60

  aiguille(cx, cy, h * 30, -R * 0.10, R * 0.50, R * 0.075, tex_bleu, BLEU)
  aiguille(cx, cy, m * 6,  -R * 0.12, R * 0.78, R * 0.035, tex_bleu, BLEU)
  disque(cx, cy, R * 0.07, BLEU)

  if trotteuse then
    aiguille(cx, cy, d.sec * 6, -R * 0.20, R * 0.86, R * 0.012, tex_rouge, ROUGE)
    disque(cx, cy, R * 0.035, ROUGE)
  end
end

-- Texte centre en chiffres a chasse fixe (l'heure ne "danse" pas quand les chiffres changent)
local function chiffres(texte, x, y, taille, c)
  local case = font:width("0", taille)
  local w = 0
  for ch in texte:gmatch(".") do
    w = w + (ch:match("%d") and case or font:width(ch, taille))
  end
  x = x - w / 2
  for ch in texte:gmatch(".") do
    local cw = ch:match("%d") and case or font:width(ch, taille)
    font:write(x + (cw - font:width(ch, taille)) / 2, y - taille / 2, ch, taille, c[1], c[2], c[3], 1)
    x = x + cw
  end
end

-- Mois/annee a gauche et jour/quantieme a droite du cadran, sur un bandeau sombre.
-- L'annee et le quantieme sont nettement plus grands que le mois et le jour.
local GRAND = 1.8

local function dates_cotes(cx, cy, R, d)
  local gauche = {MOIS[d.month], tostring(d.year)}
  local droite = {JOURS[d.wday], tostring(d.day)}

  local cote  = cx - R                -- largeur libre de chaque cote
  local max_w = cote * 0.82
  local taille = HEIGHT * 0.075
  for _, texte in ipairs{gauche[1], droite[1]} do
    local w = font:width(texte, taille)
    if w > max_w then taille = taille * max_w / w end
  end
  local w = font:width(gauche[2], taille * GRAND)
  if w > max_w then taille = taille * max_w / w end
  local grand = taille * GRAND

  local ecart = taille * 0.25
  local marge = taille * 0.40
  local haut  = cy - (taille + ecart + grand) / 2
  local bas   = haut + taille + ecart + grand
  tex_bandeau:draw(0, haut - marge, WIDTH, bas + marge)

  local y1 = haut + taille / 2
  local y2 = bas - grand / 2
  local xg = cote / 2
  local xd = WIDTH - cote / 2
  centre(gauche[1], xg, y1, taille, BLANC)
  centre(gauche[2], xg, y2, grand,  BLANC)
  centre(droite[1], xd, y1, taille, BLANC)
  centre(droite[2], xd, y2, grand,  BLANC)

  -- Heure digitale 24 h, centree sous le jour entre le bandeau et le bas de l'ecran
  local heure  = string.format("%02d:%02d", d.hour, d.min)
  local haut_h = bas + marge
  local bas_h  = HEIGHT * 0.97
  local t_h = math.min((bas_h - haut_h) * 0.70, HEIGHT * 0.16)
  w = font:width("00:00", t_h)
  if w > max_w then t_h = t_h * max_w / w end
  chiffres(heure, xd, (haut_h + bas_h) / 2, t_h, ORANGE)
end

function node.render()
  gl.clear(BLEU[1], BLEU[2], BLEU[3], 1)

  -- Bandeaux orange haut et bas
  tex_orange:draw(0, 0, WIDTH, HEIGHT * 0.03)
  tex_orange:draw(0, HEIGHT * 0.97, WIDTH, HEIGHT)

  -- Heure locale
  local t   = os.time()
  local utc = os.date("!*t", t)
  local d   = os.date("!*t", t + decalage(utc))

  -- Le cadran occupe toute la hauteur entre les bandeaux
  local cx, cy = WIDTH / 2, HEIGHT / 2
  local R = math.min(HEIGHT * 0.455, WIDTH * 0.48)

  dates_cotes(cx, cy, R, d)
  cadran(cx, cy, R)
  logo_cadran(cx, cy, R)
  aiguilles(cx, cy, R, d)
end
