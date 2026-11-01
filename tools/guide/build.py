#!/usr/bin/env python3
"""Génère l'animation « brique par brique » des deux pages d'accueil du guide lumière (FR + EN).
Usage : python3 tools/guide/build.py   (depuis n'importe où ; réécrit la section #histoire des deux pages).
Pour changer un texte ou un dessin : modifier ce fichier puis le relancer. Les styles sont dans assets/guide-motion.css,
le comportement dans assets/guide-story.js."""
import os, re, html
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

def nb(s):
    s = re.sub(r'(?<=\s)(\w{1,3}|«) ', lambda m: m.group(1) + '&nbsp;', s)
    s = re.sub(r'^(\w{1,3}|«) ', lambda m: m.group(1) + '&nbsp;', s)
    s = re.sub(r' ([?!:;»])', r'&nbsp;\1', s)
    return s.replace('« ', '«&nbsp;')

GOLD, ROSE, BLUE, GREY = '#f0bd57', '#ff5fa8', '#4d8fff', '#9aa1b0'
GREEN = '#34d17a'
TAG = {'fr': 'à confirmer', 'en': 'to confirm'}

# ---------------------------------------------------------------- textes
TXT = {
'fr': dict(
 lbl='En images', title='Votre installation, brique par brique',
 sub="Choisissez votre situation. Le dessin se construit une brique à la fois : à chaque brique, vous voyez ce qu'elle apporte et qui parle à qui.",
 aria="Schéma animé : une installation de scène construite brique par brique.",
 tabs=['DJ', 'Musiciens sur bande', 'Groupe de musique'],
 titles=['Je suis DJ', 'Je joue avec des backing tracks et des clics', 'Je joue en groupe, avec une piste clic ou des backing tracks'],
 prev='Précédent', play='Lecture', pause='Pause', next='Ajouter la brique suivante', again='Recommencer', word='Brique',
 legend=['Son', 'Ordre : numéro de cue ou commande', 'Lumière (DMX ou Art-Net)'],
 n=dict(who=['Le DJ', 'Sur scène', 'Le groupe'], mix='Table de mixage', box='MaestroDMX', mac='Mac', ipad='iPad', phone='iPhone',
        lights='Projecteurs', ez='EzQuiel', remote='Velvet Remote', prompt='prompteur', line=('entrée', 'ligne'), cue=('joue', 'la cue 7'),
        sound='le son', band='prise casque', side='Sidecar ou réseau', auto='Lecture auto', mid='ou autre appareil', mid2='MIDI ou OSC', words='paroles', art='Art-Net', dmx='DMX'),
 notes=[
  "",
  "Le détail des câbles et du routeur n'est pas montré : il dépend de votre installation.",
  "Le détail des câbles et du routeur n'est pas montré : il dépend de votre installation."],
 bricks=[
 [('Le point de départ', "Le DJ mixe avec djay sur son Mac. Le son part vers la table de mixage."),
  ('Velvet Visualizer', "Avec <b>Velvet Visualizer</b>, vous pouvez aussi voir et préparer votre lumière en 3D sur le Mac, avant la soirée, sans aucun matériel."),
  ('MaestroDMX', "Avec le boîtier <b>MaestroDMX</b>, vous pouvez aussi avoir de la lumière automatique : il écoute le son de la table, par son entrée « ligne », et joue lui-même ses ambiances sur les projecteurs. Le boîtier envoie aussi son Art-Net par le réseau : Velvet Visualizer peut le recevoir et montrer la même lumière en 3D, en direct."),
  ('Velvet Light DJ', "Avec <b>Velvet Light DJ</b>, vous pouvez aussi faire suivre la lumière à vos morceaux : l'app lit ce que vous lancez dans djay (ou Serato) et envoie au boîtier le numéro de la cue à jouer, par le réseau. Le Mac et le boîtier sont sur le même réseau.")],
 [('Le point de départ', "Une chanteuse et un chanteur-guitariste jouent sur scène. Leurs voix et leurs instruments partent vers la table de mixage. C'est souvent une table numérique comme la CQ."),
  ('Velvet Show', "Avec <b>Velvet Show</b> sur le Mac, vous pouvez aussi lancer vos backing tracks et vos clics depuis une timeline. Le son sort du Mac par la prise casque, et entre dans la même table que les voix et les instruments. Le Mac peut être sur scène ou en régie."),
  ('iPad prompteur', "Avec un <b>iPad en prompteur</b>, vous pouvez aussi afficher les paroles devant les chanteurs, au rythme de la timeline. L'iPad se relie au Mac en Sidecar (par câble, c'est le plus solide) ou par le réseau."),
  ('Velvet Visualizer', "Avec <b>Velvet Visualizer</b>, vous pouvez aussi préparer votre lumière en 3D avant le concert, sans aucun matériel."),
  ('Lumière', "Avec Velvet Show, vous pouvez aussi piloter la lumière : avec un boîtier <b>MaestroDMX</b> (l'exemple de ce guide), ou avec tout autre appareil de lumière qui comprend le MIDI ou l'OSC. Le MaestroDMX écoute aussi le son de la table, par son entrée « ligne ». Le boîtier envoie aussi son Art-Net par le réseau : Velvet Visualizer peut le recevoir et montrer la même lumière en 3D, en direct."),
  ('Cues de la timeline', "Avec les <b>cues de Velvet Show</b>, vous pouvez aussi caler la lumière sur chaque chanson : la timeline envoie à l'appareil de lumière le numéro de la cue, en OSC (par le réseau) ou en MIDI."),
  ('EzQuiel', "Avec <b>EzQuiel</b> sur un iPhone, vous pouvez aussi régler la table de mixage numérique (souvent une table comme la Allen &amp; Heath CQ), sans quitter la scène."),
  ('Velvet Remote', "Avec <b>Velvet Remote</b>, ce même iPhone devient ensuite une télécommande qui pilote Velvet Show. Un second iPhone est possible, mais facultatif."),
  ('Lancer les morceaux', "Avec Velvet Show, vous pouvez aussi lancer un morceau depuis le Mac, depuis l'iPhone, ou laisser la lecture automatique enchaîner les morceaux, avec ou sans fondu (le fondu se règle dans les réglages de Velvet Show).")],
 [('Le point de départ', "Le groupe joue ses instruments en direct, sur une piste clic ou des backing tracks. Le son des instruments part vers la table de mixage."),
  ('MaestroDMX', "Avec le boîtier <b>MaestroDMX</b>, vous pouvez aussi avoir de la lumière automatique : il écoute le son de la table, par son entrée « ligne », et joue ses ambiances sur les projecteurs."),
  ('Velvet Visualizer', "Avec <b>Velvet Visualizer</b>, vous pouvez aussi préparer votre lumière en 3D avant le concert, sans aucun matériel. Si le boîtier MaestroDMX est branché, le Visualizer reçoit aussi son Art-Net par le réseau et montre la même lumière en direct."),
  ('EzQuiel', "Avec <b>EzQuiel</b> sur un iPhone, vous pouvez aussi régler la table de mixage numérique (tables Allen &amp; Heath CQ)."),
  ('Velvet Show', "Avec <b>Velvet Show</b> sur le Mac, vous pouvez aussi lancer une piste clic ou des backing tracks, et placer vos cues de lumière sur cette piste : à chaque cue, il envoie au boîtier le numéro de la cue, par le réseau. Le son des backing tracks sort du Mac et va vers la table de mixage. Le Mac peut être en régie ou sur scène."),
  ('iPad prompteur', "Avec un <b>iPad en prompteur</b>, vous pouvez aussi afficher les paroles devant les chanteurs, au rythme de la piste. L'iPad se relie au Mac en Sidecar (par câble, c'est le plus solide) ou par le réseau."),
  ('Velvet Remote', "Avec <b>Velvet Remote</b>, l'iPhone devient une télécommande qui pilote Velvet Show : un membre du groupe lance les morceaux et les cues depuis la scène, ou un technicien depuis le Mac en régie. Vous pouvez aussi laisser la lecture automatique enchaîner les morceaux.")],
 ]),
'en': dict(
 lbl='In pictures', title='Your setup, brick by brick',
 sub="Pick your situation. The picture builds one brick at a time: each brick shows what it adds and who talks to whom.",
 aria="Animated diagram: a stage setup built brick by brick.",
 tabs=['DJ', 'Musicians on tracks', 'Live band'],
 titles=['I am a DJ', 'I play along with backing tracks and click tracks', 'I play in a band, with a click track or backing tracks'],
 prev='Previous', play='Play', pause='Pause', next='Add the next brick', again='Start over', word='Brick',
 legend=['Sound', 'Order: cue number or command', 'Light (DMX or Art-Net)'],
 n=dict(who=['The DJ', 'On stage', 'The band'], mix='Mixing desk', box='MaestroDMX', mac='Mac', ipad='iPad', phone='iPhone',
        lights='Lights', ez='EzQuiel', remote='Velvet Remote', prompt='teleprompter', line=('line', 'input'), cue=('play', 'cue 7'),
        sound='sound', band='headphone jack', side='Sidecar or network', auto='Auto play', mid='or other device', mid2='MIDI or OSC', words='lyrics', art='Art-Net', dmx='DMX'),
 notes=[
  "",
  "Exact cables and router are not shown: they depend on your setup.",
  "Exact cables and router are not shown: they depend on your setup."],
 bricks=[
 [('The starting point', "The DJ mixes with djay on a Mac. The sound goes to the mixing desk."),
  ('Velvet Visualizer', "With <b>Velvet Visualizer</b>, you can also see and prepare your lighting in 3D on the Mac, before the night, with no hardware at all."),
  ('MaestroDMX', "With the <b>MaestroDMX</b> box, you can also get automatic lighting: it listens to the sound from the desk, through its \"line\" input, and plays its own looks on the lights. The box also sends its Art-Net over the network: Velvet Visualizer can receive it and show the same lighting in 3D, live."),
  ('Velvet Light DJ', "With <b>Velvet Light DJ</b>, you can also make the lights follow your tracks: the app reads what you play in djay (or Serato) and sends the box the number of the cue to play, over the network. The Mac and the box are on the same network.")],
 [('The starting point', "A female singer and a singer-guitarist play on stage. Their voices and instruments go to the mixing desk. It is often a digital desk like the CQ."),
  ('Velvet Show', "With <b>Velvet Show</b> on the Mac, you can also start your backing tracks and click tracks from a timeline. The sound leaves the Mac through the headphone jack and enters the same desk as the voices and instruments. The Mac can be on stage or at the booth."),
  ('iPad teleprompter', "With an <b>iPad as a teleprompter</b>, you can also show the lyrics in front of the singers, in time with the timeline. The iPad connects to the Mac through Sidecar (by cable, the most reliable) or over the network."),
  ('Velvet Visualizer', "With <b>Velvet Visualizer</b>, you can also prepare your lighting in 3D before the show, with no hardware at all."),
  ('Lighting', "With Velvet Show, you can also control the lighting: with a <b>MaestroDMX</b> box (the example in this guide), or with any other lighting device that understands MIDI or OSC. The MaestroDMX also listens to the sound from the desk, through its \"line\" input. The box also sends its Art-Net over the network: Velvet Visualizer can receive it and show the same lighting in 3D, live."),
  ('Timeline cues', "With <b>Velvet Show cues</b>, you can also time the light to each song: the timeline sends the lighting device the cue number, over OSC (on the network) or MIDI."),
  ('EzQuiel', "With <b>EzQuiel</b> on an iPhone, you can also adjust the digital mixing desk (often a desk like the Allen &amp; Heath CQ) without leaving the stage."),
  ('Velvet Remote', "With <b>Velvet Remote</b>, that same iPhone then becomes a remote control for Velvet Show. A second iPhone is possible, but optional."),
  ('Starting songs', "With Velvet Show, you can also start a song from the Mac, from the iPhone, or let automatic playback chain the songs, with or without a crossfade (the crossfade is set in Velvet Show's settings).")],
 [('The starting point', "The band plays live instruments, along with a click track or backing tracks. The sound of the instruments goes to the mixing desk."),
  ('MaestroDMX', "With the <b>MaestroDMX</b> box, you can also get automatic lighting: it listens to the sound from the desk, through its \"line\" input, and plays its own looks on the lights."),
  ('Velvet Visualizer', "With <b>Velvet Visualizer</b>, you can also prepare your lighting in 3D before the show, with no hardware at all. If the MaestroDMX box is connected, the Visualizer also receives its Art-Net over the network and shows the same lighting live."),
  ('EzQuiel', "With <b>EzQuiel</b> on an iPhone, you can also adjust the digital mixing desk (Allen &amp; Heath CQ desks)."),
  ('Velvet Show', "With <b>Velvet Show</b> on the Mac, you can also start a click track or backing tracks, and place your lighting cues on that track: at each cue, it sends the box the cue number, over the network. The sound of the backing tracks leaves the Mac and goes to the mixing desk. The Mac can be at the booth or on stage."),
  ('iPad teleprompter', "With an <b>iPad as a teleprompter</b>, you can also show the lyrics in front of the singers, in time with the track. The iPad connects to the Mac through Sidecar (by cable is the most solid) or over the network."),
  ('Velvet Remote', "With <b>Velvet Remote</b>, the iPhone becomes a remote control for Velvet Show: a band member starts the songs and cues from the stage, or a technician does it from the Mac at the booth. You can also let automatic playback chain the songs.")],
 ]),
}

# ---------------------------------------------------------------- dessin
def person(x, col, kind, d):
    body = f'<circle cx="{x}" cy="118" r="15" fill="#f4c9a0"/><rect x="{x-14}" y="136" width="28" height="42" rx="12" fill="{col}"/><rect x="{x-12}" y="172" width="9" height="18" rx="3" fill="#2a2e3a"/><rect x="{x+3}" y="172" width="9" height="18" rx="3" fill="#2a2e3a"/>'
    ex = {
     'singer': f'<ellipse cx="{x}" cy="127" rx="5" ry="4" fill="#3a2418"/><line x1="{x+14}" y1="148" x2="{x+24}" y2="130" stroke="#f4c9a0" stroke-width="6" stroke-linecap="round"/><circle cx="{x+26}" cy="126" r="5" fill="#9aa1b0"/>',
     'singerf': f'<path d="M{x-14} 108 q14 -14 28 0" fill="#5a3416"/><circle cx="{x-18}" cy="116" r="6" fill="#5a3416"/><ellipse cx="{x}" cy="127" rx="5" ry="4" fill="#3a2418"/><line x1="{x+14}" y1="148" x2="{x+24}" y2="130" stroke="#f4c9a0" stroke-width="6" stroke-linecap="round"/><circle cx="{x+26}" cy="126" r="5" fill="#9aa1b0"/>',
     'gsing': f'<path d="M{x-14} 152 L{x+16} 170" stroke="#f4c9a0" stroke-width="6" stroke-linecap="round"/><ellipse cx="{x+14}" cy="166" rx="15" ry="10" fill="#e8a020" transform="rotate(-25 {x+14} 166)"/><line x1="{x+22}" y1="160" x2="{x+46}" y2="140" stroke="#8a5a2b" stroke-width="4" stroke-linecap="round"/><line x1="{x-22}" y1="190" x2="{x-22}" y2="128" stroke="#565c6e" stroke-width="3"/><circle cx="{x-22}" cy="124" r="5" fill="#9aa1b0"/>',
     'guitar': f'<path d="M{x-14} 152 L{x+16} 170" stroke="#f4c9a0" stroke-width="6" stroke-linecap="round"/><ellipse cx="{x+14}" cy="166" rx="15" ry="10" fill="#e8a020" transform="rotate(-25 {x+14} 166)"/><line x1="{x+22}" y1="160" x2="{x+46}" y2="140" stroke="#8a5a2b" stroke-width="4" stroke-linecap="round"/>',
     'drum': f'<ellipse cx="{x}" cy="182" rx="26" ry="9" fill="#565c6e"/><ellipse cx="{x}" cy="180" rx="26" ry="7" fill="#9aa1b0"/><line x1="{x-14}" y1="148" x2="{x-26}" y2="166" stroke="#f4c9a0" stroke-width="5" stroke-linecap="round"/><line x1="{x+14}" y1="148" x2="{x+26}" y2="166" stroke="#f4c9a0" stroke-width="5" stroke-linecap="round"/>',
     'keys': f'<rect x="{x-26}" y="166" width="52" height="12" rx="3" fill="#10121a" stroke="#9aa1b0"/><path d="M{x-20} 166 v12 M{x-10} 166 v12 M{x} 166 v12 M{x+10} 166 v12 M{x+20} 166 v12" stroke="#9aa1b0"/><line x1="{x-12}" y1="150" x2="{x-14}" y2="166" stroke="#f4c9a0" stroke-width="5" stroke-linecap="round"/><line x1="{x+12}" y1="150" x2="{x+14}" y2="166" stroke="#f4c9a0" stroke-width="5" stroke-linecap="round"/>',
     'dj': f'<path d="M{x-17} 118 a17 17 0 0 1 34 0" fill="none" stroke="#eceef3" stroke-width="4"/><rect x="{x-35}" y="164" width="70" height="26" rx="5" fill="#2a2e3a" stroke="#565c6e"/><circle cx="{x-16}" cy="177" r="9" fill="#10121a" stroke="#9aa1b0"/><circle cx="{x+16}" cy="177" r="9" fill="#10121a" stroke="#9aa1b0"/><line x1="{x-12}" y1="150" x2="{x-14}" y2="168" stroke="#f4c9a0" stroke-width="5" stroke-linecap="round"/><line x1="{x+12}" y1="150" x2="{x+14}" y2="168" stroke="#f4c9a0" stroke-width="5" stroke-linecap="round"/>',
    }[kind]
    return f'<g class="ch" style="--d:{d}s">{body}{ex}</g>'

def notes(xs):
    return '<g aria-hidden="true">' + ''.join(f'<text x="{x}" y="{y}" class="note" style="--k:{i}">{c}</text>' for i, (x, y, c) in enumerate(xs)) + '</g>'

def br(b, inner, cls='', halo=GOLD):
    return f'<g class="br {cls}" data-b="{b}" style="--halo:{halo}">{inner}</g>'

def arrow(sid, b, d, col, dash=False):
    return f'<path class="br arrow{" dash" if dash else ""}" data-b="{b}" d="{d}" stroke="{col}" fill="none" stroke-width="5" stroke-linecap="round" marker-end="url(#m{sid}{col[1:]})"/>'

def txt(b, x, y, s, col, anchor='middle', cls='lab sm', lines=None):
    if lines:
        t = f'<tspan x="{x}" dy="0">{lines[0]}</tspan><tspan x="{x}" dy="21">{lines[1]}</tspan>'
    else:
        t = s
    return f'<text class="br {cls}" data-b="{b}" x="{x}" y="{y}" text-anchor="{anchor}" fill="{col}">{t}</text>'

def tagtxt(b, x, y, L, anchor='middle'):
    return f'<text class="br tg" data-b="{b}" x="{x}" y="{y}" text-anchor="{anchor}">{TAG[L]}</text>'

def table_dev(n, b=None):
    inner = f'<rect x="20" y="318" width="148" height="96" rx="12" class="devbox"/><circle cx="52" cy="352" r="9" fill="{GOLD}"/><circle cx="86" cy="352" r="9" fill="{ROSE}"/><circle cx="120" cy="352" r="9" fill="{BLUE}"/><rect x="46" y="378" width="12" height="22" rx="3" fill="#565c6e"/><rect x="80" y="388" width="12" height="12" rx="3" fill="#565c6e"/><rect x="114" y="372" width="12" height="28" rx="3" fill="#565c6e"/><text x="94" y="438" text-anchor="middle" class="lab b">{n["mix"]}</text>'
    return f'<g class="dev" data-b="0" data-now="0">{inner}</g>'

def box_dev(n, b, sub=False):
    inner = f'<rect x="278" y="318" width="104" height="96" rx="12" class="devbox"/><rect x="292" y="332" width="76" height="14" rx="4" fill="#0d0e12"/><circle cx="302" cy="339" r="3.5" fill="#34d17a"/><circle cx="330" cy="378" r="16" fill="none" stroke="{GOLD}" stroke-width="3"/><circle cx="330" cy="378" r="4" fill="{GOLD}"/><text x="330" y="438" text-anchor="middle" class="lab b">{n["box"]}</text>' + (f'<text x="330" y="458" text-anchor="middle" class="lab sm" fill="{GREY}">{n["mid"]}</text><text x="330" y="477" text-anchor="middle" class="lab sm" fill="{GREY}">{n["mid2"]}</text>' if sub else '')
    return br(b, inner, 'dev', GOLD)

def mac_dev(n, b, screen_extra='', base_screen=''):
    inner = f'<rect x="490" y="326" width="136" height="80" rx="8" class="devbox"/><rect x="500" y="336" width="116" height="60" rx="3" fill="#0d0e12"/>{base_screen}<path d="M478 406 H638 L630 428 H486 Z" fill="#565c6e"/><text x="558" y="422" text-anchor="middle" class="mt">{n["mac"]}</text>'
    return br(b, inner, 'dev', GREY), screen_extra

def badge(b, slot, label, col, icon=''):
    y = 284 - slot * 32
    inner = f'<rect x="466" y="{y}" width="170" height="28" rx="14" class="badge" stroke="{col}"/><circle cx="484" cy="{y+14}" r="5" fill="{col}"/><text x="496" y="{y+19}" class="bdt" fill="#eceef3">{label}</text>'
    return br(b, inner, 'bd', col)

def viz_screen(b):
    return br(b, f'<path d="M506 372 L560 352 L612 372 L560 388 Z" fill="#171a22" stroke="#323847"/><polygon points="520,368 530,368 540,384 510,384" fill="{ROSE}" opacity=".5"/><polygon points="555,358 565,358 575,376 545,376" fill="{BLUE}" opacity=".55"/><polygon points="588,366 598,366 606,382 580,382" fill="{GOLD}" opacity=".5"/>', 'scr', BLUE)

def timeline_screen(b):
    bars = ''.join(f'<rect x="{506+i*14}" y="{376-h}" width="9" height="{h}" rx="2" fill="{c}" opacity=".85"/>' for i, (h, c) in enumerate([(10, BLUE), (18, ROSE), (8, GOLD), (22, ROSE), (14, BLUE), (20, GOLD), (9, ROSE), (16, BLUE)]))
    return br(b, bars + f'<line x1="506" y1="388" x2="610" y2="388" stroke="#565c6e" stroke-width="2"/>', 'scr', GOLD)

def wave_screen():
    d = 'M506 372 ' + ' '.join(f'l6 {(-1)**i*(6+(i*5)%10)}' for i in range(16))
    return f'<path d="{d}" fill="none" stroke="{GOLD}" stroke-width="2" opacity=".8"/>'

def phone(x, label, sub, b, n, line2=''):
    cx = x + 36
    inner = f'<rect x="{x}" y="478" width="72" height="84" rx="12" class="devbox"/><rect x="{x+8}" y="488" width="56" height="52" rx="4" fill="#0d0e12"/><rect x="{x+14}" y="496" width="44" height="14" rx="4" fill="{ROSE}" opacity=".85"/><text x="{cx}" y="528" text-anchor="middle" class="lab sm" fill="{GREY}">{sub}</text><circle cx="{cx}" cy="551" r="3" fill="#565c6e"/><text x="{cx}" y="584" text-anchor="middle" class="lab b">{label}</text><text x="{cx}" y="604" text-anchor="middle" class="lab sm" fill="{GREY}">{line2}</text>'
    return br(b, inner, 'dev', ROSE)

def ipad(b, n):
    inner = f'<rect x="196" y="484" width="132" height="70" rx="10" class="devbox"/><rect x="204" y="492" width="116" height="54" rx="4" fill="#0d0e12"/><text x="262" y="514" text-anchor="middle" class="lab sm" fill="{GOLD}">♪ {n["words"]}</text><rect x="214" y="524" width="80" height="4" rx="2" fill="#565c6e"/><rect x="214" y="533" width="56" height="4" rx="2" fill="#565c6e"/><text x="262" y="578" text-anchor="middle" class="lab b">{n["ipad"]}</text><text x="262" y="598" text-anchor="middle" class="lab sm" fill="{GREY}">{n["prompt"]}</text>'
    return br(b, inner, 'dev', GOLD)

def lamps(b):
    out = ''
    for i, (x, c) in enumerate([(390, ROSE), (470, BLUE), (550, GOLD)]):
        out += f'<g class="lamp" data-b="{b}" style="--c:{c};--i:{i}"><polygon class="beam" points="{x-9},58 {x+9},58 {x+42},190 {x-42},190" fill="{c}"/><rect x="{x-14}" y="40" width="28" height="20" rx="5" class="lampbody"/><circle cx="{x}" cy="62" r="6" class="bulb"/></g>'
    return out

def markers(sid):
    return ''.join(f'<marker id="m{sid}{c[1:]}" viewBox="0 0 10 10" refX="6" refY="5" markerWidth="4.2" markerHeight="4.2" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>' for c in (GOLD, ROSE, BLUE, GREY))

def svg(si, L, ttl):
    n = TXT[L]['n']; sid = f's{si}'
    parts = []
    # scène
    parts.append('<rect x="6" y="6" width="628" height="204" rx="16" class="stage"/><rect x="6" y="190" width="628" height="20" class="floor"/><line x1="350" y1="36" x2="600" y2="36" class="truss"/>')
    parts.append(f'<text x="470" y="26" text-anchor="middle" class="lab" fill="{GREY}">{n["lights"]}</text>')
    people = {0: [(110, '#9b6bff', 'dj')], 1: [(70, '#ff5fa8', 'singerf'), (160, '#9b6bff', 'gsing')],
              2: [(40, '#ff5fa8', 'singer'), (98, '#9b6bff', 'guitar'), (178, '#34d17a', 'drum'), (244, '#ff6b35', 'keys')]}[si]
    parts += [person(x, c, k, round(.3 * i, 2)) for i, (x, c, k) in enumerate(people)]
    parts.append(notes([(people[0][0] + 20, 106, '♪'), (people[-1][0] + 30, 110, '♫'), (30, 96, '♪')]))
    parts.append(f'<text x="115" y="32" text-anchor="middle" class="lab" fill="{GREY}">{n["who"][si]}</text>')
    ART_B = {0: 2, 1: 4, 2: 1}[si]      # brique du boîtier
    parts.append(lamps(ART_B))
    parts.append(table_dev(n))
    parts.append(box_dev(n, ART_B, si == 1))
    # boîtier : ligne + lumière
    parts.append(arrow(sid, ART_B, 'M168 366 L276 366', GOLD))
    parts.append(txt(ART_B, 222, 322, '', GOLD, lines=n['line']))
    parts.append(arrow(sid, ART_B, 'M330 316 V36 H346', BLUE))
    parts.append(txt(ART_B, 340, 240, n['dmx'], BLUE, anchor='start'))
    macb = {0: 0, 1: 1, 2: 2}[si]
    slots = 0
    L_ = L
    if si == 0:
        mac, _ = mac_dev(n, 0, base_screen=wave_screen())
        parts += [mac, badge(0, slots, 'djay', GOLD)]; slots += 1
        parts.append(arrow(sid, 0, 'M490 346 H452 V296 H150 V312', GOLD))
        parts.append(txt(0, 300, 286, n['sound'], GOLD))
        parts.append(badge(1, slots, 'Velvet Visualizer', BLUE)); parts.append(viz_screen(1)); slots += 1
        parts.append(badge(3, slots, 'Velvet Light DJ', ROSE)); slots += 1
        parts.append(arrow(sid, 3, 'M478 366 L388 366', ROSE))
        parts.append(txt(3, 434, 394, '', ROSE, lines=n['cue']))
        parts.append(br(3, f'<rect x="-28" y="-15" width="56" height="30" rx="15" fill="{ROSE}"/><text x="0" y="6" text-anchor="middle" class="bt">cue 7</text>', 'bubble', ROSE))
    elif si == 1:
        parts.append(arrow(sid, 0, 'M115 214 L95 312', GOLD)); parts.append(txt(0, 128, 246, n['sound'], GOLD, anchor='start'))
        mac, _ = mac_dev(n, 1)
        parts += [mac, badge(1, slots, 'Velvet Show', GOLD), timeline_screen(1)]; slots += 1
        parts.append(arrow(sid, 1, 'M490 346 H452 V296 H150 V312', GOLD))
        parts.append(txt(1, 215, 286, n['band'], GOLD))
        parts.append(ipad(2, n)); parts.append(arrow(sid, 2, 'M500 434 L336 522', ROSE, True)); parts.append(txt(2, 420, 548, n['side'], ROSE))
        parts.append(badge(3, slots, 'Velvet Visualizer', BLUE)); parts.append(viz_screen(3)); slots += 1
        parts.append(arrow(sid, 5, 'M478 366 L388 366', ROSE)); parts.append(txt(5, 434, 394, '', ROSE, lines=n['cue']))
        parts.append(br(5, f'<rect x="-28" y="-15" width="56" height="30" rx="15" fill="{ROSE}"/><text x="0" y="6" text-anchor="middle" class="bt">cue 7</text>', 'bubble', ROSE))
        parts.append(phone(20, n['phone'], 'CQ', 6, n, n['ez'])); parts.append(arrow(sid, 6, 'M56 474 L56 448', ROSE, True))
        parts.append(phone(512, n['phone'], 'cue 7', 7, n, n['remote'])); parts.append(arrow(sid, 7, 'M548 474 L548 434', ROSE)); parts.append(badge(8, slots + 0, n['auto'], GREEN)); parts.append(br(8, f'<path d="M512 392 l10 -6 v12 z" fill="{GREEN}"/>', 'scr', GREEN))
    else:
        parts.append(arrow(sid, 0, 'M115 214 L95 312', GOLD)); parts.append(txt(0, 128, 272, n['sound'], GOLD, anchor='start'))
        mac, _ = mac_dev(n, 2)
        parts += [mac, badge(2, slots, 'Velvet Visualizer', BLUE), viz_screen(2)]; slots += 1
        parts.append(phone(20, n['phone'], 'CQ', 3, n, n['ez'])); parts.append(arrow(sid, 3, 'M56 474 L56 448', ROSE, True))
        parts.append(badge(4, slots, 'Velvet Show', GOLD)); parts.append(timeline_screen(4)); slots += 1
        parts.append(arrow(sid, 4, 'M490 346 H452 V296 H150 V312', GOLD)); parts.append(txt(4, 300, 286, n['sound'], GOLD))
        parts.append(arrow(sid, 4, 'M478 366 L388 366', ROSE)); parts.append(txt(4, 434, 394, '', ROSE, lines=n['cue']))
        parts.append(br(4, f'<rect x="-28" y="-15" width="56" height="30" rx="15" fill="{ROSE}"/><text x="0" y="6" text-anchor="middle" class="bt">cue 7</text>', 'bubble', ROSE))
        parts.append(ipad(5, n)); parts.append(arrow(sid, 5, 'M500 434 L336 522', ROSE, True)); parts.append(txt(5, 420, 548, n['side'], ROSE))
        parts.append(phone(512, n['phone'], 'cue 7', 6, n, n['remote'])); parts.append(arrow(sid, 6, 'M548 474 L548 434', ROSE))
    LINK_B = {0: 2, 1: 4, 2: 2}[si]      # brique où le boîtier et le Visualizer sont tous deux là
    parts.append(arrow(sid, LINK_B, 'M388 332 L486 332', BLUE)); parts.append(txt(LINK_B, 410, 320, n['art'], BLUE))
    return f'<svg class="story-svg" viewBox="0 0 640 {460 if si == 0 else 612}" role="img" aria-label="{ttl}" data-b="0"><defs>{markers(sid)}</defs>{"".join(parts)}</svg>'

def section(L):
    T = TXT[L]
    setups = ''
    for si in range(3):
        caps = ''.join(f'<li><b class="capapp">{a}</b> {nb(t)}</li>' for a, t in T['bricks'][si])
        note = f'<p class="story-note nojs">{nb(T["notes"][si])}</p>' if T['notes'][si] else ''
        setups += f'''<div class="setup" data-setup="{si}" data-note="{html.escape(nb(T['notes'][si]).replace('&nbsp;', chr(160)))}">
<h3 class="setup-title">{nb(T['titles'][si])}</h3>
<div class="story-stage">{svg(si, L, T['titles'][si])}</div>
<ol class="story-caps">{caps}</ol>{note}
</div>
'''
    tabs = ''.join(f'<button type="button" role="tab" id="tab-{L}-{i}" aria-selected="false" tabindex="-1" data-tab="{i}">{nb(t)}</button>' for i, t in enumerate(T['tabs']))
    leg = ''.join(f'<li><i class="{c}"></i>{nb(s)}</li>' for c, s in zip('aon', T['legend']))
    return f'''<section class="feature" id="histoire"><div class="wrap">
<p class="lbl lbl-pink">{nb(T['lbl'])}</p>
<h2 class="sec-title">{nb(T['title'])}</h2>
<p class="sec-sub">{nb(T['sub'])}</p>
<figure class="fig wide story" data-story data-word="{T['word']}" aria-label="{T['aria']}">
<div class="story-tabs" role="tablist" hidden>{tabs}</div>
{setups}<p id="story-caption" class="demo-caption" aria-live="polite" hidden></p>
<div class="story-ctrl" hidden><button type="button" data-prev>← {T['prev']}</button><button type="button" class="play" data-play data-l-play="{T['play']}" data-l-pause="{T['pause']}">{T['pause']}</button><button type="button" class="next" data-next data-l-next="{T['next']} +" data-l-again="{T['again']} ↺">{T['next']} +</button><span class="story-count"></span></div>
<div class="story-dots" role="group" hidden></div>
<ul class="legend">{leg}</ul>
<p class="story-note shared" hidden></p>
</figure>
</div></section>
'''

PAGES = {'fr': 'fr/lumiere-de-scene-en-5-minutes.html', 'en': 'stage-lighting-in-5-minutes.html'}
if __name__ == '__main__':
    for L, rel in PAGES.items():
        p = os.path.join(ROOT, rel); h = open(p, encoding='utf-8').read()
        h2, k = re.subn(r'<section class="feature" id="histoire">.*?</section>\n', lambda m: section(L), h, count=1, flags=re.S)
        assert k == 1, rel
        open(p, 'w', encoding='utf-8').write(h2); print('ok', rel)
