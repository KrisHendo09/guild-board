"""Draws the patch notes poster on the board art. Edit the feature text, run it, commit the png."""
import os
from PIL import Image, ImageDraw, ImageFont
HERE=os.path.dirname(os.path.abspath(__file__)); R=os.path.join(HERE,'art')+'/'
OUTP=os.path.join(HERE,'..','images','announce','patch_notes_1_3.png')
W,H=1200,800
im=Image.open(R+'board_bg.png').convert('RGBA').resize((W,H),Image.LANCZOS)
F=lambda s,w='Regular':ImageFont.truetype(R+f'fonts/Poppins-{w}.ttf',s)
GOLD='#E8B964';TXT='#F1E9DA';MUTE='#B9AD98'
def T(d,xy,s,f,fill,a='lm'):
    d.text((xy[0]+1,xy[1]+2),s,font=f,fill=(0,0,0,220),anchor=a); d.text(xy,s,font=f,fill=fill,anchor=a)
def card(im,box,accent,alpha=205):
    ov=Image.new('RGBA',im.size,(0,0,0,0));o=ImageDraw.Draw(ov)
    o.rounded_rectangle(box,10,fill=(12,9,7,alpha),outline=(232,185,100,110))
    o.rounded_rectangle([box[0],box[1],box[0]+6,box[3]],3,fill=accent)
    return Image.alpha_composite(im,ov)
d=ImageDraw.Draw(im)
T(d,(W//2,96),'Guild Board 1.3',F(42,'Bold'),GOLD,'mm')
T(d,(W//2,140),'PATCH NOTES  ·  PUSH TO PROD',F(15,'Medium'),MUTE,'mm')
X0,X1=58,1142
# tooltip legend strip
y=214
im=card(im,[X0,y,X1,y+92],(232,185,100,255));d=ImageDraw.Draw(im)
T(d,(X0+24,y+28),'HOVER ANY ITEM',F(13,'Bold'),GOLD)
T(d,(X0+24,y+60),'The tooltip tells you who in the guild wants it',F(15),MUTE)
pills=[('Needs','someone asked',(70,140,255)),('Mats','profession grind',(240,200,60)),('Upgrade','beats their gear',(90,200,110)),('Crafter','can make it',(232,150,60))]
px=470
for name,sub,c in pills:
    d.rounded_rectangle([px,y+20,px+156,y+72],9,fill=(0,0,0,0),outline=c+(255,),width=2)
    d.ellipse([px+14,y+39,px+28,y+53],fill=c)
    T(d,(px+38,y+36),name,F(16,'Bold'),TXT); d.text((px+38,y+58),sub,font=F(12,'Medium'),fill=MUTE,anchor='lm')
    px+=168
# feature grid 3x2
feats=[('Dungeon Finder','Click the minimap button, pick the dungeons you want. Guildies in range see it.',(196,60,40)),
('Dings and Level Race','Popups when a guildie levels, plus who is leading the pack.',(232,185,100)),
('Death Log','Every guild death and what got them. No hiding.',(150,40,40)),
('Shared Quests','See who is on the same quests and in your zone.',(90,170,120)),
('Hearths and Flights','Know who can get where before you ask for a summon.',(80,140,220)),
('Mailbox and Gear Check','Send needs from the mailbox. Check party gear before you pull.',(170,120,220))]
gy=322;cols=3;gap=14;cw=(X1-X0-gap*2)/3;chh=(690-gy-gap)/2
for i,(t,s,c) in enumerate(feats):
    cx=int(X0+(i%3)*(cw+gap));cy=int(gy+(i//3)*(chh+gap))
    im=card(im,[cx,cy,int(cx+cw),int(cy+chh)],c+(255,));d=ImageDraw.Draw(im)
    T(d,(cx+26,cy+48),t,F(24,'Bold'),TXT)
    # wrap
    words=s.split();lines=[];cur=''
    for w in words:
        if d.textlength(cur+' '+w,font=F(17))>cw-52: lines.append(cur);cur=w
        else: cur=(cur+' '+w).strip()
    lines.append(cur)
    for j,l in enumerate(lines): T(d,(cx+26,cy+96+j*28),l,F(17),MUTE)
T(d,(W//2,722),'Update from GitHub now  ·  CurseForge auto updates coming soon  ·  /gb bug to report issues',F(14,'Medium'),GOLD,'mm')
im.convert('RGB').save(OUTP,optimize=True)
