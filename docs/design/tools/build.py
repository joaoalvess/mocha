import math, os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'mock.html')
ICONS = dict(l.split(' ', 1) for l in open(os.path.join(HERE, 'icons.txt')).read().strip().split('\n'))

CSS = r"""
:root{
  --bg:#1E1E1E;--drawerBg:#161719;--scrim:#0F0F10;--tp:#FCFCFC;--ts:#98A0A8;--link:#78A0F4;--userBubble:#1B351B;
  --selectedRow:#142E16;--toolCard:#121416;--toolBorder:#303438;--controlBg:#202225;--controlSel:#121416;--claude:#D87454;
  --git:#FB923C;--ok:#00FF00;--dirty:#F4B450;--error:#D8383C;--termText:#D4D8E0;--accBar:#424242;--accKey:#272829;
  --black:#010102;--badgeOk:#0F3712;--badgeWarn:#342C1F;--sepDot:#55595F;--ringTrack:#2F3032;--divider:#202223;
  --barTrack:#191B1D;--paceMark:#979899;--claudeTile:#2E221F;--heroBg:#120A08;--heroTile:#2E1914;--tableBorder:#2B2B2B;
  --codeInner:#17191B;--grabber:#47474B;
  --mono:"JetBrains Mono","JetBrainsMono Nerd Font",ui-monospace,SFMono-Regular,Menlo,monospace;
  --sf:-apple-system,BlinkMacSystemFont,"SF Pro Text","SF Pro","Helvetica Neue",sans-serif;
}
*{box-sizing:border-box;margin:0;padding:0}
html{background:#08080A}
body{font-family:var(--sf);color:#E4E5E8;-webkit-font-smoothing:antialiased;padding:44px 48px 140px;min-width:1360px}
.ic{display:block;flex:none;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round}
.fill{fill:currentColor;stroke:none}

.top h1{font:700 30px/36px var(--sf);letter-spacing:-.5px;color:#F5F5F7}
.top .lead{margin-top:6px;font:400 15px/22px var(--sf);color:#8E939A}
.legend{display:flex;flex-wrap:wrap;gap:12px 26px;margin-top:20px;align-items:center}
.legend .it{display:flex;align-items:center;gap:9px;font:400 13px/18px var(--sf);color:#9DA2A9}
.ph{display:inline-flex;align-items:center;height:22px;padding:0 9px;border-radius:11px;font:600 12px/1 var(--sf);letter-spacing:.2px;white-space:nowrap}
.ph.core{background:#0F3712;color:#00FF00}.ph.fin{background:#172241;color:#78A0F4}.ph.b{background:#342C1F;color:#F4B450}.ph.f2{background:#202225;color:#A8AEB5}
.grp{margin-top:66px}
.grp>h2{font:600 12px/16px var(--sf);letter-spacing:1.4px;text-transform:uppercase;color:#6B7077;padding-top:18px;border-top:1px solid #18191C;margin-bottom:26px}
.row{display:flex;flex-wrap:wrap;gap:52px 40px;align-items:flex-start}
.shot{width:412px;flex:none}
.shot-h{display:flex;align-items:center;gap:8px;margin:0 6px 14px;min-height:24px}
.shot-h .nm{font:600 15px/20px var(--sf);color:#F2F2F4;margin-right:2px}
.phone{width:412px;padding:11px;border-radius:58px;background:#050506;box-shadow:inset 0 0 0 1.5px #2A2B2F,inset 0 0 0 4px #0B0B0C,0 30px 70px -20px rgba(0,0,0,.8)}
.screen{position:relative;width:390px;height:844px;border-radius:47px;overflow:hidden;background:var(--bg);color:var(--tp);isolation:isolate;font-family:var(--sf)}
.note{margin:16px 8px 0;font:400 13px/19px var(--sf);color:#9A9FA6}
.note p+p{margin-top:7px}
.note b{color:#D9DBDF;font-weight:600}
.note code{font:500 12px var(--mono);color:#B8C4E0}
.variants{display:flex;gap:10px;flex-wrap:wrap;margin:14px 8px 0;padding:14px;border-radius:16px;background:#0E0F11;align-items:center}
.variants .cap{width:100%;font:400 12px/16px var(--sf);color:#7D828A;margin-bottom:2px}

.sb{position:absolute;left:0;right:0;top:0;height:47px;z-index:90;pointer-events:none;color:#fff}
.sb .t{position:absolute;left:0;width:127px;top:15px;text-align:center;font:600 17px/22px var(--sf);letter-spacing:-.3px}
.sb .ics{position:absolute;right:26px;top:19px;display:flex;align-items:center;gap:6px}
.hi{position:absolute;left:50%;bottom:8px;width:134px;height:5px;margin-left:-67px;border-radius:3px;background:#F2F2F2;z-index:95}

.gl{-webkit-backdrop-filter:blur(14px) saturate(1.5);backdrop-filter:blur(14px) saturate(1.5);box-shadow:inset 0 0 0 1px rgba(255,255,255,.14),inset 1.2px 1.6px 1px -1px rgba(255,255,255,.32),inset -1px -1.4px 1px -1px rgba(255,255,255,.10),0 10px 26px rgba(0,0,0,.35)}
.gl-chat{background:rgba(66,66,66,.8)}
.gl-cmp{background:rgba(62,62,62,.84)}
.gl-home{background:rgba(62,78,64,.5)}
.gl-pill{background:rgba(96,100,106,.5)}
.gl-hero{background:rgba(84,74,72,.5)}
.gl-black{background:rgba(60,60,62,.55)}

.home{background:radial-gradient(260px 330px at 50% 40px,rgba(0,255,0,.078),rgba(0,255,0,0)),radial-gradient(250px 240px at 100% 100%,rgba(0,255,0,.115),rgba(0,255,0,0)),var(--black)}
.gbtn{position:absolute;top:47px;width:44px;height:44px;border-radius:22px;display:grid;place-items:center;color:#fff;z-index:30}
.gbtn.l{left:16px}.gbtn.r{right:16px}.gbtn.r2{right:68px}
.gbtn .ic{width:21px;height:21px;stroke-width:1.8}
.gbtn .bdg{position:absolute;right:-2px;top:-2px;min-width:18px;height:18px;border-radius:9px;background:var(--dirty);color:#1a1206;font:700 11px/18px var(--sf);text-align:center;padding:0 5px}
.list{position:absolute;left:0;right:0;top:121px}
.sec{margin:12px 16px 8px;font:400 12px/16px var(--sf);letter-spacing:.25px;color:var(--ts);text-transform:uppercase}
.hc{position:relative;margin:0 16px 8px;min-height:65.3px;padding:12.5px 44px 12px 68px;background:var(--toolCard);border-radius:16px}
.hc .t1{font:600 16px/21px var(--sf);color:var(--tp);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.hc .t2{font:400 14px/21px var(--sf);color:var(--ts);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.hc .t2.warn{color:var(--dirty)}
.hc .meta{display:flex;align-items:center;height:17.3px;margin-top:2.5px;white-space:nowrap}
.hc .t2+.meta{margin-top:5.5px}
.hc .chev{position:absolute;right:17px;top:50%;margin-top:-9.5px;width:12px;height:19px;color:var(--ts);stroke-width:2.3}
.hc.dim .t1{color:#C9CCD0}
.hc.warn{box-shadow:inset 0 0 0 1px rgba(244,180,80,.3)}
.badge{display:inline-flex;align-items:center;height:17.3px;padding:0 7px;border-radius:5px;background:var(--badgeOk);color:var(--ok);font:600 11px/1 var(--sf);letter-spacing:.1px}
.meta .sep{width:4px;height:4px;border-radius:50%;background:var(--sepDot);margin:0 6.5px 0 6.3px;flex:none}
.meta .cc{font:500 12px/1 var(--sf);color:var(--claude)}
.meta .tm{font:400 12px/1 var(--sf);color:var(--ts)}
.ring{position:absolute;left:16px;top:50%;margin-top:-20px;width:40px;height:40px}
.ring svg{position:absolute;left:0;top:0;width:40px;height:40px;overflow:visible}
.ring .n{position:absolute;inset:0;display:grid;place-items:center;font:600 11px/1 var(--sf);color:var(--tp);letter-spacing:-.1px}
.ring .n.d{color:var(--ts)}
.upill{position:absolute;left:22px;right:22px;top:763px;height:38px;border-radius:19px;display:flex;align-items:center;padding:0 16px 0 15px;z-index:30}
.upill .h{display:flex;align-items:center;flex:1;min-width:0}
.upill .dv{width:1px;height:18px;background:rgba(255,255,255,.13);margin:0 14px}
.upill .ast{width:16px;height:16px;color:var(--claude);stroke-width:2.1;margin-right:8px}
.upill .lb{font:500 12px/1 var(--mono);color:var(--ts);margin-right:8px}
.upill .bar{flex:1;height:4px;border-radius:2px;background:var(--barTrack);position:relative;overflow:hidden}
.upill .bar i{position:absolute;left:0;top:0;bottom:0;background:var(--ok);border-radius:2px}
.upill .pc{font:500 12px/1 var(--mono);color:var(--tp);margin-left:8px}
.offcap{position:absolute;left:50%;top:58px;transform:translateX(-50%);height:24px;border-radius:12px;padding:0 11px 0 9px;display:flex;align-items:center;gap:7px;font:500 13px/1 var(--sf);color:#D0D3D7;white-space:nowrap;z-index:30}
.offcap i{width:7px;height:7px;border-radius:50%;background:var(--ts)}
.empty{position:absolute;left:32px;right:32px;top:300px;text-align:center}
.empty .et{width:64px;height:64px;border-radius:18px;background:var(--claudeTile);display:grid;place-items:center;color:var(--claude);margin:0 auto}
.empty .et .ic{width:36px;height:36px;stroke-width:1.9}
.empty h3{margin-top:22px;font:600 19px/24px var(--sf)}
.empty p{margin-top:8px;font:400 15px/21px var(--sf);color:var(--ts)}
.empty .eb{display:inline-flex;align-items:center;gap:8px;margin-top:22px;height:44px;padding:0 20px;border-radius:22px;background:var(--toolCard);font:600 15px/1 var(--sf)}
.empty .eb .ic{width:19px;height:19px}

.sheet{position:absolute;left:0;right:0;top:372px;bottom:0;background:var(--drawerBg);border-radius:38px 38px 0 0;z-index:50;box-shadow:0 -1px 0 rgba(255,255,255,.05),0 -10px 40px rgba(0,0,0,.4)}
.grab{position:absolute;left:50%;top:9px;width:34px;height:4.5px;margin-left:-17px;border-radius:3px;background:var(--grabber)}
.sheet h3{position:absolute;left:21px;top:46px;font:700 17px/22px var(--sf)}
.sheet .upd{position:absolute;right:21px;top:48px;font:400 13px/20px var(--sf);color:var(--ts)}
.ucard{position:absolute;left:20px;right:20px;top:87.3px;background:var(--toolCard);border-radius:15px}
.uhd{display:flex;align-items:center;padding:0 16px;height:66px}
.tile{width:40px;height:40px;border-radius:11px;background:var(--claudeTile);display:grid;place-items:center;color:var(--claude);flex:none}
.tile .ic{width:25px;height:25px;stroke-width:1.9}
.uhd .tx{flex:1;min-width:0;margin-left:13.3px}
.uhd .a{font:600 16px/21px var(--sf);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.uhd .b{font:400 12px/16px var(--sf);color:var(--ts);margin-top:3.5px}
.uhd .ago{font:400 12px/16px var(--sf);color:var(--ts);margin-left:10px;white-space:nowrap}
.udiv{height:1px;background:var(--divider)}
.bars{padding:8.7px 17.3px 0 16px}
.br{display:flex;align-items:center;height:24px}
.br .l{width:38.7px;text-align:right;font:400 11px/1 var(--mono);color:var(--ts);flex:none}
.br .bt{position:relative;margin-left:13.3px;width:153.7px;height:6px;border-radius:3px;background:var(--barTrack);flex:none}
.br .bt i{position:absolute;left:0;top:0;bottom:0;border-radius:3px;background:var(--ok)}
.br .bt b{position:absolute;top:-2px;width:2px;height:10px;border-radius:1px;background:var(--paceMark)}
.br .p{width:47.3px;text-align:right;font:400 12px/1 var(--mono);color:var(--tp);flex:none}
.br .r{flex:1;text-align:right;font:400 12px/1 var(--sf);color:var(--ts)}
.pace{padding:9px 16px 10px;font:400 14px/20px var(--sf);color:var(--ts)}
.ufoot{position:absolute;left:36px;right:36px;top:272px;font:400 12px/17px var(--sf);color:#6F747B;text-align:center}

.dsheet{position:absolute;left:0;right:0;top:47px;bottom:0;background:var(--black);border-radius:38px 38px 0 0}
.dflow{position:absolute;left:16px;right:16px;top:51px}
.hero{position:relative;border-radius:22px;background:var(--heroBg);text-align:center;padding:23.7px 26px 24.3px}
.hero .ht{width:80px;height:80px;border-radius:22px;background:var(--heroTile);display:grid;place-items:center;color:var(--claude);margin:0 auto}
.hero .ht .ic{width:48px;height:48px;stroke-width:1.75}
.hero h2{margin-top:16.7px;font:700 24px/28px var(--sf);letter-spacing:-.35px;display:-webkit-box;-webkit-line-clamp:4;-webkit-box-orient:vertical;overflow:hidden}
.hero .hm{margin-top:7.9px;font:400 15px/20px var(--sf);color:var(--ts)}
.hero .hm .w{font:400 15px var(--mono);color:var(--ok);letter-spacing:-.2px}
.hero .hm .w.warn{color:var(--dirty)}
.hero .hb{margin-top:15.4px;display:flex;justify-content:center}
.xbtn{position:absolute;left:16px;top:63px;width:44px;height:44px;border-radius:22px;display:grid;place-items:center;color:#fff;z-index:20}
.xbtn .ic{width:19px;height:19px;stroke-width:2.1}
.stb{display:inline-flex;align-items:center;height:25px;padding:0 12px;border-radius:12.5px;border:2px solid var(--ok);background:#0F2E07;color:var(--ok);font:700 11px/1 var(--sf);letter-spacing:.9px;position:relative;white-space:nowrap}
.stb.work::before,.stb.work::after{content:"";position:absolute;top:-2.5px;width:7px;height:3px;background:var(--heroBg)}
.stb.work::before{left:26%}.stb.work::after{left:64%}
.stb.ready{border-color:#0F2E07}
.stb.need{border-color:var(--dirty);color:var(--dirty);background:#2A1E0D}
.variants .stb.work::before,.variants .stb.work::after{background:#0E0F11}
.obtn{margin-top:20.3px;height:52px;border-radius:26px;background:var(--toolCard);display:flex;align-items:center;justify-content:center;gap:11px;font:600 16px/1 var(--sf)}
.obtn .ic{width:19px;height:19px;stroke-width:2}
.dcard{background:var(--toolCard);border-radius:14px}
.acct{margin-top:20.3px;height:91.7px;padding:12px 16.7px 0 16.3px}
.acct .hd{display:flex;justify-content:space-between;font:400 14px/20px var(--sf);color:var(--ts);white-space:nowrap}
.acct .rows{margin-top:3.7px}
.acct .br .l{width:63.7px;text-align:left}
.acct .br .bt{margin-left:0;width:141.7px}
.acct .br .p{width:48.3px;color:var(--ts)}
.dtab{margin-top:16.3px}
.dtab .tr{display:flex;align-items:center;height:44px;padding:0 16.7px 0 16.3px;font:400 14px/1 var(--sf);color:var(--ts);white-space:nowrap}
.dtab .tr+.tr{border-top:1px solid var(--divider);height:45px}
.dtab .tr .v{margin-left:auto;display:flex;align-items:center;gap:10px}
.dtab .tr .v.m{font:400 13.5px/1 var(--mono)}
.dtab .tr .v .ic{width:16px;height:16px;stroke-width:1.8}
.scrollind{position:absolute;right:3.3px;top:171px;width:3px;height:180px;border-radius:2px;background:#767677;z-index:20}

.chat{position:absolute;left:0;right:0;padding:0 16px;font:400 14.67px/20px var(--mono);color:var(--tp)}
.chat .p{margin-bottom:12px}
.chat .p b,.chat li b{font-weight:700}
.ci{color:var(--link)}
.chat h4{font:700 16px/22px var(--mono);margin:0 0 8px}
.chat ul{list-style:none;margin:0 0 12px}
.chat li{position:relative;padding-left:25.3px;margin-bottom:4px}
.chat li::before{content:"\2022";position:absolute;left:12px;top:0}
.tools{display:flex;flex-direction:column;gap:6px;margin-bottom:12px}
.tool{display:flex;align-items:center;height:32px;border-radius:16px;background:var(--toolCard);padding:0 15px 0 12.7px;font:400 12px/16px var(--mono);color:var(--ts);white-space:nowrap}
.tool .ti{width:15px;height:15px;margin-right:6.6px;stroke-width:1.9}
.tool .sm{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}
.tool .nm{color:var(--tp);font-weight:700}
.tool .st{width:15px;height:15px;margin-left:10px;stroke-width:2}
.tool .st.err{color:var(--error);stroke-width:1.8}
.tool .spin{width:13px;height:13px;margin-left:10px;border-radius:50%;border:1.8px solid rgba(152,160,168,.25);border-top-color:var(--ts)}
.texp{background:var(--toolCard);border-radius:16px;margin-top:0}
.texp .tool{background:none}
.texp .inner{margin:0 12px;padding:10px 12px 12px;background:var(--codeInner);border-radius:10px;font:400 12px/18px var(--mono);color:var(--ts)}
.texp .inner .cmd{color:var(--tp);padding-left:14.4px;text-indent:-14.4px}
.texp .inner .cmd .dl{color:var(--link)}
.texp .inner .out{margin-top:12px;white-space:pre;overflow:hidden}
.texp .pad{height:12px}
.think{font-style:italic;color:var(--ts);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-bottom:12px}
.foot{font-style:italic;color:var(--ts);margin-bottom:12px}
.recap{font-style:italic;color:var(--ts);margin-bottom:12px}
.recap b{font-weight:700}
.ub{margin:0 0 12px auto;width:fit-content;max-width:85%;background:var(--userBubble);border-radius:16px;padding:8px 14px}
.ub.pend{opacity:.5;margin-bottom:5px}
.pendl{display:flex;justify-content:flex-end;align-items:center;gap:5px;margin:0 3px 12px 0;font:400 11px/14px var(--mono);color:var(--ts)}
.pendl .ic{width:12px;height:12px;stroke-width:2}
.notice{text-align:center;font:400 12px/16px var(--mono);color:var(--ts);margin-bottom:12px}
.chip{display:flex;justify-content:flex-end;margin-bottom:12px}
.chip span{display:inline-flex;align-items:center;height:26px;padding:0 12px;border-radius:13px;background:var(--toolCard);font:700 12px/1 var(--mono);color:var(--tp)}
.tbl{width:100%;border-collapse:separate;border-spacing:0;border:1px solid var(--tableBorder);border-radius:10px;font:400 12px/18px var(--mono);margin-bottom:12px;overflow:hidden}
.tbl th,.tbl td{padding:6px 8px;text-align:left;vertical-align:top;border-bottom:1px solid var(--tableBorder);border-right:1px solid var(--tableBorder)}
.tbl tr>*:last-child{border-right:0}
.tbl tr:last-child>*{border-bottom:0}
.tbl th{font-weight:700}
.code{position:relative;background:var(--toolCard);border-radius:12px;padding:10px 0 15px 12px;font:400 12px/18px var(--mono);white-space:pre;overflow:hidden;margin-bottom:12px;color:var(--tp)}
.code .fade{position:absolute;right:0;top:0;bottom:0;width:40px;background:linear-gradient(90deg,rgba(18,20,22,0),var(--toolCard) 80%)}
.code .sbar{position:absolute;left:12px;bottom:5px;width:150px;height:3px;border-radius:2px;background:rgba(255,255,255,.3)}
.code .cm{color:var(--ts)}
.status{display:flex;align-items:center;height:20px;font:400 12px/16px var(--mono);margin-bottom:12px;white-space:nowrap}
.status .as{width:10px;height:10px;margin:0 8px 0 1px;color:var(--tp);stroke-width:2.4}
.status .e{color:var(--ts);margin-left:7px}
.stop{margin-left:auto;width:20px;height:20px;position:relative;flex:none}
.stop svg{position:absolute;inset:0}
.stop i{position:absolute;left:6.5px;top:6.5px;width:7px;height:7px;border-radius:1.6px;background:var(--tp)}

.hdr{position:absolute;left:12px;right:12px;top:48px;height:62px;border-radius:31px;z-index:40}
.hdr .dot{position:absolute;left:16px;top:23px;width:16px;height:16px;border-radius:50%;background:var(--ok)}
.hdr .dot::after{content:"";position:absolute;left:4.6px;top:7.25px;width:6.8px;height:1.6px;border-radius:1px;background:#000}
.hdr .dot.pulse{box-shadow:0 0 0 4px rgba(0,255,0,.16),0 0 12px 2px rgba(0,255,0,.35)}
.hdr .dot.warn{background:var(--dirty)}
.hdr .dot.off{background:var(--ts)}
.hdr .ast{position:absolute;left:43.5px;top:15.5px;width:15px;height:15px;color:var(--claude);stroke-width:2.3}
.hdr .ttl{position:absolute;left:65px;right:92px;top:12px;font:700 16px/22px var(--mono);white-space:nowrap;overflow:hidden}
.hdr .sub{position:absolute;left:44px;right:92px;top:34px;font:400 12px/16px var(--mono);color:var(--ts);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.hdr .hb{position:absolute;top:17px;width:28px;height:28px;border-radius:50%;background:#9BA0AA;display:grid;place-items:center;color:#000}
.hdr .hb .ic{width:16px;height:16px;stroke-width:2.1}
.hdr .hb.git{right:52px;opacity:.32}
.hdr .hb.nav{right:16px}
.cmp{position:absolute;left:12px;right:12px;bottom:47px;height:48px;border-radius:24px;display:flex;align-items:center;padding:0 6px 0 16px;z-index:40}
.cmp .phd{flex:1;min-width:0;font:400 14px/20px var(--mono);color:var(--ts);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cmp .phd.draft{color:var(--tp)}
.sendb{width:36px;height:36px;border-radius:18px;background:#49494B;display:grid;place-items:center;color:var(--ts);flex:none}
.sendb.on{background:var(--tp);color:#1E1E1E}
.sendb .ic{width:18px;height:18px;stroke-width:2.3}
.down{position:absolute;right:12px;bottom:103px;width:38px;height:38px;border-radius:19px;display:grid;place-items:center;color:#fff;z-index:41}
.down .ic{width:19px;height:19px;stroke-width:2.1}
.cmpx{position:absolute;left:12px;right:12px;border-radius:26px;z-index:40;padding:13px 0 6px}
.cmpx .fld{padding:0 16px;font:400 14px/20px var(--mono);color:var(--tp)}
.caret{display:inline-block;width:2px;height:17px;margin-left:1px;background:var(--ok);vertical-align:-3px;border-radius:1px}
.cmpx .brow{display:flex;align-items:center;height:44px;margin-top:6px;padding:0 6px 0 8px}
.cmpx .bb{width:40px;height:36px;display:grid;place-items:center;color:var(--tp)}
.cmpx .bb .ic{width:21px;height:21px;stroke-width:1.9}
.cmpx .bb.act{background:rgba(255,255,255,.12);border-radius:18px}
.cmpx .sp{flex:1}

.kbd{position:absolute;left:0;right:0;top:544px;bottom:0;background:#222222;border-radius:30px 30px 0 0;z-index:60;box-shadow:inset 0 1px 0 rgba(255,255,255,.06)}
.key{position:absolute;height:43px;border-radius:8.5px;background:#464646;color:#fff;display:grid;place-items:center;font:400 23px/1 var(--sf)}
.key .ic{width:22px;height:22px;stroke-width:1.7}
.key.sm{font:400 17px/1 var(--sf)}
.key .pt{position:absolute;right:10px;bottom:5px;font:500 11px/1 var(--sf);color:#8E8E93}
.kicon{position:absolute;width:28px;height:28px;color:#fff}
.kicon .ic{width:28px;height:28px;stroke-width:1.5}

.menu{position:absolute;left:12px;width:268px;border-radius:26px;background:rgba(40,40,42,.97);-webkit-backdrop-filter:blur(30px) saturate(1.6);backdrop-filter:blur(30px) saturate(1.6);box-shadow:inset 0 0 0 .6px rgba(255,255,255,.12),inset 1px 1.5px 1px -1px rgba(255,255,255,.25),0 22px 60px rgba(0,0,0,.6);padding:7px 0;z-index:70}
.mi{display:flex;align-items:center;min-height:52px;padding:7px 18px 7px 18px;gap:14px}
.mi .ic{width:21px;height:21px;color:var(--tp);stroke-width:1.8}
.mi .l{font:600 15px/19px var(--mono);color:var(--tp)}
.mi .d{font:400 13px/17px var(--sf);color:var(--ts)}
.mi.red .ic,.mi.red .l{color:#F0555A}
.msep{height:1px;margin:5px 18px;background:rgba(255,255,255,.1)}
.scrimf{position:absolute;inset:0;background:rgba(0,0,0,.5);z-index:65}
.alert{position:absolute;left:45px;right:45px;top:300px;border-radius:32px;background:rgba(44,44,46,.9);-webkit-backdrop-filter:blur(30px);backdrop-filter:blur(30px);box-shadow:inset 0 0 0 .6px rgba(255,255,255,.12),0 22px 60px rgba(0,0,0,.6);padding:22px 18px 16px;text-align:center;z-index:70}
.alert h5{font:600 17px/22px var(--sf)}
.alert p{font:400 14px/19px var(--sf);color:#C5C8CD;margin-top:6px}
.alert p code{font:500 13px var(--mono);color:var(--link)}
.alert .ab{display:flex;gap:10px;margin-top:18px}
.alert .ab div{flex:1;height:46px;border-radius:23px;background:rgba(255,255,255,.1);display:grid;place-items:center;font:600 16px/1 var(--sf)}
.alert .ab .red{color:#F0555A}

.pcard{background:var(--toolCard);border-radius:18px;box-shadow:inset 0 0 0 1px rgba(244,180,80,.3);padding:12px 12px;margin-bottom:12px}
.pcard .h1{display:flex;align-items:center;gap:7px;height:18px;font:700 12px/16px var(--mono);color:var(--dirty);padding-left:2px}
.pcard .h1 .ic{width:15px;height:15px;stroke-width:2}
.pcard .h1 .tm{margin-left:auto;color:var(--ts);font-weight:400}
.pcard .pt{margin:9px 2px 0;font:400 14.67px/20px var(--mono)}
.pcard .pt .ts{color:var(--ts)}
.pcard .inner{margin-top:10px;background:var(--codeInner);border-radius:10px;padding:9px 12px;font:400 12px/18px var(--mono);color:var(--ts)}
.pcard .inner .c{color:var(--tp)}
.pcard .more{display:flex;align-items:center;gap:4px;margin:8px 2px 0;font:400 12px/16px var(--mono);color:var(--ts)}
.pcard .more .ic{width:12px;height:12px;stroke-width:2.2}
.pbtns{display:flex;gap:8px;margin-top:12px}
.pbtns div{flex:1;height:42px;border-radius:21px;display:grid;place-items:center;font:600 15px/1 var(--sf)}
.pbtns .no{background:var(--controlBg);color:var(--tp)}
.pbtns .yes{background:var(--ok);color:#021402}
.opts{margin-top:10px;display:flex;flex-direction:column;gap:2px}
.opt{display:flex;gap:11px;align-items:flex-start;padding:9px 10px;border-radius:12px}
.opt.sel{background:var(--selectedRow)}
.opt .rd{width:18px;height:18px;border-radius:50%;border:1.6px solid #5E646B;flex:none;margin-top:1px}
.opt .rd.on{border:5px solid var(--ok);background:#021402}
.opt .ol{font:400 14px/20px var(--mono)}
.opt .od{font:400 12px/16px var(--sf);color:var(--ts);margin-top:1px}
.other{margin-top:8px;height:40px;border-radius:12px;background:var(--codeInner);display:flex;align-items:center;padding:0 12px;font:400 13px/1 var(--mono);color:var(--ts)}
.pbtns .ans{flex:none;width:130px;margin-left:auto;background:var(--ok);color:#021402}

.scrim{position:absolute;inset:0;background:rgba(0,0,0,.5);z-index:60}
.drawer{position:absolute;left:0;top:0;bottom:0;width:351px;background:var(--drawerBg);z-index:70;box-shadow:14px 0 40px rgba(0,0,0,.45)}
.dtop{position:absolute;left:16px;right:16px;top:55px;height:44px;display:flex;align-items:center;gap:8px}
.srch{flex:1;min-width:0;height:44px;border-radius:22px;background:#191B1D;display:flex;align-items:center;padding:0 14px 0 13px;gap:9px;color:var(--ts);font:400 16px/1 var(--sf)}
.srch .ic{width:19px;height:19px;stroke-width:2}
.srch span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.seg{display:flex;align-items:center;width:86px;height:34px;border-radius:17px;background:var(--controlBg);padding:0 3px;flex:none}
.seg div{flex:1;height:28px;border-radius:14px;display:grid;place-items:center;color:var(--ts)}
.seg div.on{background:var(--controlSel);color:var(--tp)}
.seg .ic{width:18px;height:18px;stroke-width:1.9}
.dgear{width:34px;height:34px;border-radius:17px;background:var(--controlBg);display:grid;place-items:center;color:var(--ts);flex:none}
.dgear .ic{width:19px;height:19px;stroke-width:1.8}
.dsec{position:absolute;left:20.3px;top:116px;font:600 11px/16px var(--sf);letter-spacing:.3px;color:var(--ts)}
.tree{position:absolute;left:0;right:0;top:135px}
.dr{position:relative;display:flex;align-items:center;height:36px;margin:0 16.3px 0 16px;border-radius:10px;font:400 15px/20px var(--sf);color:var(--tp);white-space:nowrap}
.dr.sel{background:var(--selectedRow)}
.dr .cv{position:absolute;top:13.5px;width:10px;height:10px;color:var(--ts);stroke-width:2.2}
.dr .wn{font-weight:500}
.dr .br2{display:flex;align-items:center;margin-left:8.4px;font:400 13px/1 var(--sf);color:var(--ts)}
.dr .br2 .ic{width:12.5px;height:12.5px;margin-right:3px;stroke-width:1.8}
.dr .dy{margin-left:7px;color:var(--dirty);font:400 21px/1 var(--sf);transform:translateY(4px)}
.dr .ti{position:absolute;top:11.5px;width:13px;height:13px}
.dr .ti.cl{color:var(--claude);stroke-width:2.4}
.dr .ti.sh{color:var(--ts);stroke-width:2.2}
.dr .ti.pl{filter:drop-shadow(0 0 3px rgba(216,116,84,.95)) drop-shadow(0 0 6px rgba(216,116,84,.6))}
.dr .tx{overflow:hidden;text-overflow:ellipsis}
.dr .bd{position:absolute;right:12px;top:14px;width:8px;height:8px;border-radius:50%;background:var(--dirty)}
.dr.col .tx{color:var(--tp)}
.dr .add{position:absolute;right:2px;top:4px;width:28px;height:28px;display:grid;place-items:center;color:var(--ts)}
.dr .add .ic{width:14px;height:14px;stroke-width:2}
.rr{display:flex;align-items:center;height:56px;margin:0 16.3px 0 16px;padding:0 12px 0 10.7px;border-radius:12px;gap:11px}
.rr.sel{background:var(--selectedRow)}
.rr .ti{width:14px;height:14px;color:var(--claude);stroke-width:2.4}
.rr .ti.pl{filter:drop-shadow(0 0 3px rgba(216,116,84,.95)) drop-shadow(0 0 6px rgba(216,116,84,.6))}
.rr .c{flex:1;min-width:0}
.rr .t{font:400 15px/20px var(--sf);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rr .s{font:400 13px/17px var(--sf);color:var(--ts);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rr .bd{width:8px;height:8px;border-radius:50%;background:var(--dirty);flex:none}
.dhint{position:absolute;left:24px;right:24px;bottom:44px;font:400 12px/16px var(--sf);color:#5F646B;text-align:center}

.stitle{position:absolute;left:0;right:0;top:74px;text-align:center;font:600 17px/22px var(--sf)}
.sbody{position:absolute;left:16px;right:16px;top:124px}
.slab{font:400 12px/16px var(--sf);letter-spacing:.25px;text-transform:uppercase;color:var(--ts);margin:0 16px 7px}
.scard{background:var(--toolCard);border-radius:14px}
.srow{display:flex;align-items:center;min-height:44px;padding:0 16px;font:400 15px/20px var(--sf);white-space:nowrap}
.srow+.srow{border-top:1px solid var(--divider)}
.srow .v{margin-left:auto;color:var(--ts);display:flex;align-items:center;gap:7px}
.srow .v.m{font:400 13.5px/1 var(--mono)}
.srow .v.warn{color:var(--dirty)}
.srow .v i{width:8px;height:8px;border-radius:50%;background:var(--ok)}
.srow.center{justify-content:center;color:#F0555A;font-weight:500}
.sfoot{font:400 12px/16px var(--sf);color:var(--ts);margin:7px 16px 0}
.sgap{height:26px}
.hostrow{display:flex;align-items:center;gap:13px;padding:13px 16px}
.hostrow .tile{background:#1C2A1E;color:var(--ok)}
.hostrow .a{font:600 16px/21px var(--sf)}
.hostrow .b{font:400 13px/17px var(--sf);color:var(--ts);margin-top:1px}
.tog{width:51px;height:31px;border-radius:16px;background:var(--ok);position:relative;margin-left:auto;flex:none}
.tog::after{content:"";position:absolute;right:2px;top:2px;width:27px;height:27px;border-radius:50%;background:#fff;box-shadow:0 2px 5px rgba(0,0,0,.3)}

.pair .logo{position:absolute;left:50%;top:148px;margin-left:-44px;width:88px;height:88px;border-radius:24px;background:linear-gradient(165deg,#221813,#130d0b);box-shadow:inset 0 0 0 .7px rgba(255,255,255,.1),0 16px 40px rgba(0,0,0,.5);display:grid;place-items:center;color:var(--claude)}
.pair .logo .ic{width:54px;height:54px;stroke-width:1.9}
.pair h1{position:absolute;left:0;right:0;top:262px;text-align:center;font:700 26px/32px var(--sf);letter-spacing:-.4px}
.pair .lead{position:absolute;left:40px;right:40px;top:302px;text-align:center;font:400 15px/21px var(--sf);color:var(--ts)}
.steps{position:absolute;left:16px;right:16px;top:376px;background:var(--toolCard);border-radius:16px;padding:6px 0}
.step{display:flex;gap:12px;padding:10px 16px;align-items:flex-start;font:400 15px/21px var(--sf)}
.step .n{width:22px;height:22px;border-radius:11px;background:var(--controlBg);display:grid;place-items:center;font:600 12px/1 var(--sf);color:var(--ts);flex:none;margin-top:-.5px}
.step code{font:500 14px var(--mono);color:var(--link)}
.cta{position:absolute;left:16px;right:16px;height:52px;border-radius:26px;background:var(--tp);color:#0A0A0A;display:flex;align-items:center;justify-content:center;gap:10px;font:600 17px/1 var(--sf)}
.cta .ic{width:21px;height:21px;stroke-width:2}
.linkf{position:absolute;left:16px;right:16px;height:48px;border-radius:24px;background:var(--toolCard);display:flex;align-items:center;padding:0 6px 0 16px;gap:10px;color:var(--ts);font:400 13px/1 var(--mono)}
.linkf .ic{width:17px;height:17px;stroke-width:2}
.linkf .pb{margin-left:auto;height:36px;padding:0 16px;border-radius:18px;background:var(--controlBg);display:grid;place-items:center;font:600 14px/1 var(--sf);color:var(--tp)}
.errc{position:absolute;left:16px;right:16px;border-radius:16px;background:rgba(216,56,60,.11);box-shadow:inset 0 0 0 1px rgba(216,56,60,.38);padding:13px 16px;display:flex;gap:12px;font:400 15px/21px var(--sf)}
.errc .ic{width:20px;height:20px;color:#F0555A;stroke-width:2;margin-top:.5px}
.errc code{font:500 14px var(--mono);color:var(--link)}
.errc .s{font:400 13px/18px var(--sf);color:var(--ts);margin-top:3px}
.cam{background:radial-gradient(300px 260px at 50% 45%,#22262b 0%,#101214 60%,#070809 100%)}
.cam .scr{position:absolute;left:62px;top:228px;width:266px;height:290px;border-radius:10px;background:#0b0c0e;transform:perspective(700px) rotateX(8deg) rotateZ(-3deg);box-shadow:0 0 0 7px #16181b,0 30px 60px rgba(0,0,0,.6);filter:blur(.3px)}
.cam .scr .tl{position:absolute;left:14px;top:12px;font:400 9px/12px var(--mono);color:#6b7078;white-space:pre}
.cam .scr svg{position:absolute;left:58px;top:60px;width:150px;height:150px}
.ret{position:absolute;left:78px;top:238px;width:234px;height:234px;z-index:10}
.ret i{position:absolute;width:46px;height:46px;border:4px solid var(--ok);filter:drop-shadow(0 0 6px rgba(0,255,0,.5))}
.ret i:nth-child(1){left:0;top:0;border-right:0;border-bottom:0;border-radius:18px 0 0 0}
.ret i:nth-child(2){right:0;top:0;border-left:0;border-bottom:0;border-radius:0 18px 0 0}
.ret i:nth-child(3){left:0;bottom:0;border-right:0;border-top:0;border-radius:0 0 0 18px}
.ret i:nth-child(4){right:0;bottom:0;border-left:0;border-top:0;border-radius:0 0 18px 0}
.camcap{position:absolute;left:50%;transform:translateX(-50%);height:40px;border-radius:20px;padding:0 18px;display:flex;align-items:center;gap:9px;font:500 15px/1 var(--sf);white-space:nowrap;z-index:20}
.camcap .sp{width:14px;height:14px;border-radius:50%;border:2px solid rgba(255,255,255,.25);border-top-color:#fff}
.camtitle{position:absolute;left:0;right:0;top:128px;text-align:center;font:600 17px/22px var(--sf);z-index:20}
.camsub{position:absolute;left:40px;right:40px;top:154px;text-align:center;font:400 14px/19px var(--sf);color:#C9CCD1;z-index:20}
.camsub code{font:500 13px var(--mono);color:#fff}

.lock{background:radial-gradient(430px 380px at 18% 16%,#0d3a1b 0%,rgba(13,58,27,0) 70%),radial-gradient(430px 430px at 92% 88%,#3a190e 0%,rgba(58,25,14,0) 70%),linear-gradient(#08090a,#050506)}
.lk-car{position:absolute;left:28px;top:15px;font:600 16px/22px var(--sf);z-index:91}
.lk-lock{position:absolute;left:50%;top:54px;margin-left:-9px;width:18px;height:22px;color:#fff}
.lk-lock .ic{width:18px;height:22px}
.lk-date{position:absolute;left:0;right:0;top:86px;text-align:center;font:600 20px/24px var(--sf);color:rgba(255,255,255,.86)}
.lk-time{position:absolute;left:0;right:0;top:106px;text-align:center;font:700 108px/112px var(--sf);letter-spacing:-3px;color:rgba(255,255,255,.93)}
.la{position:absolute;left:12px;right:12px;top:452px;border-radius:24px;background:rgba(18,20,22,.8);-webkit-backdrop-filter:blur(24px);backdrop-filter:blur(24px);padding:14px 16px 13px;box-shadow:inset 0 0 0 .6px rgba(255,255,255,.08)}
.la .top{display:flex;align-items:center;gap:11px}
.la .top .tile{width:34px;height:34px;border-radius:10px}
.la .top .tile .ic{width:21px;height:21px}
.la .k{font:600 16px/20px var(--sf)}
.la .k em{font-style:normal;color:var(--dirty)}
.la .kk{font:400 13px/17px var(--sf);color:var(--ts)}
.la .hl{margin-top:12px;padding-top:11px;border-top:1px solid rgba(255,255,255,.08);display:flex;align-items:center;gap:10px}
.la .hl i{width:9px;height:9px;border-radius:50%;background:var(--dirty);flex:none}
.la .hl .c{flex:1;min-width:0}
.la .hl .a{font:600 15px/19px var(--sf);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.la .hl .b{font:400 13px/17px var(--sf);color:var(--ts);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.la .hl .tmr{font:600 16px/1 var(--mono);color:var(--dirty)}
.la .wk{display:flex;align-items:center;gap:10px;margin-top:10px}
.la .wk i{width:9px;height:9px;border-radius:50%;background:var(--ok);flex:none;box-shadow:0 0 6px rgba(0,255,0,.6)}
.la .wk .a{flex:1;font:400 14px/18px var(--sf);color:#D6D8DC;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.la .wk .tmr{font:500 14px/1 var(--mono);color:var(--ts)}
.nt{position:absolute;left:12px;right:12px;border-radius:24px;z-index:92;background:rgba(62,62,64,.58);-webkit-backdrop-filter:blur(24px) saturate(1.4);backdrop-filter:blur(24px) saturate(1.4);box-shadow:inset 0 0 0 .6px rgba(255,255,255,.1),0 10px 30px rgba(0,0,0,.3);padding:13px 15px 13px 13px;display:flex;gap:11px}
.appic{width:38px;height:38px;border-radius:9.5px;background:linear-gradient(165deg,#241914,#140e0b);box-shadow:inset 0 0 0 .6px rgba(255,255,255,.12);display:grid;place-items:center;color:var(--claude);flex:none}
.appic .ic{width:25px;height:25px;stroke-width:2}
.nt .c{flex:1;min-width:0}
.nt .r1{display:flex;align-items:baseline;gap:8px}
.nt .a{font:600 15px/20px var(--sf);flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.nt .w{font:400 13px/1 var(--sf);color:rgba(255,255,255,.55)}
.nt .b{font:400 15px/20px var(--sf);color:rgba(255,255,255,.88);display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.lk-btn{position:absolute;bottom:38px;width:50px;height:50px;border-radius:25px;background:rgba(40,40,42,.6);-webkit-backdrop-filter:blur(20px);backdrop-filter:blur(20px);display:grid;place-items:center;color:#fff}
.lk-btn .ic{width:22px;height:22px;stroke-width:1.8}

.term{background:#010101}
.tsheet{position:absolute;left:0;right:0;top:47px;bottom:0;background:var(--bg);border-radius:38px 38px 0 0;overflow:hidden}
.tgrab{position:absolute;left:50%;top:8px;width:36px;height:4px;margin-left:-18px;border-radius:2px;background:#5B5B5F}
.thd{position:absolute;left:20px;right:14px;top:15px;height:16px;display:flex;align-items:center}
.thd .dot{position:relative;width:16px;height:16px;border-radius:50%;background:var(--ok);flex:none}
.thd .dot::after{content:"";position:absolute;left:4.6px;top:7.25px;width:6.8px;height:1.6px;border-radius:1px;background:#000}
.thd .h{margin-left:10px;font:400 12px/16px var(--mono);color:var(--ts);flex:1;white-space:nowrap;overflow:hidden}
.thd .mb{width:22px;height:22px;border-radius:50%;display:grid;place-items:center;color:#000;margin-left:8px;flex:none}
.thd .mb .ic{width:13px;height:13px;stroke-width:2.2}
.tl{position:absolute;left:8.3px;right:0;font:400 13.8px/18.6px var(--mono);color:var(--termText);white-space:pre}
.tl .s{color:#999}.tl .lk{color:#8FA6F2}.tl .y{color:#F8D383}.tl .yb{color:#F5BC40}.tl .bl{color:#84D3FA}.tl .b{font-weight:700}.tl .i{font-style:italic;color:#999}
.tbar{position:absolute;left:8.3px;right:4px;top:30px;height:37px;display:flex}
.tbar .l{flex:1;background:#181825;padding:0 8px;font:400 13.8px/18.6px var(--mono);color:#7F839C;white-space:pre;overflow:hidden}
.tbar .r{width:66px;background:#303244;color:#CDD5F4;font:700 13.8px/1 var(--mono);display:flex;align-items:flex-end;justify-content:center;padding-bottom:3px}
.trule{position:absolute;left:8.3px;right:8.3px;height:1px;background:#6E6E6E}
.acc{position:absolute;left:4.3px;right:4.3px;top:487px;height:51px;border-radius:25.5px;display:flex;align-items:center;padding:0 6px 0 9px;gap:6px;z-index:61}
.acc .k{height:34px;min-width:34px;padding:0 9px;border-radius:10px;background:var(--accKey);display:grid;place-items:center;font:400 14px/1 var(--mono);color:var(--tp)}
.acc .k .ic{width:18px;height:18px;stroke-width:1.8}
.acc .k.g{background:rgba(39,40,41,.55)}
.acc .grp2{margin-left:auto;display:flex;gap:6px;padding-left:8px;border-left:1px solid rgba(255,255,255,.1)}

.ph.sub{background:#2E221F;color:#D87454}
.sa{background:var(--toolCard);border-radius:16px;padding:8px 15px 8px 12.7px;font:400 12px/16px var(--mono);color:var(--ts)}
.sa .r{display:flex;align-items:center;height:16px;white-space:nowrap}
.sa .r+.r{margin-top:6px}
.sa .ti{width:15px;height:15px;margin-right:6.6px;stroke-width:1.9}
.sa .sm{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}
.sa .nm{color:var(--tp);font-weight:700}
.sa .ind{width:21.6px;flex:none}
.sa .ai{width:13px;height:13px;margin-right:6px;stroke-width:1.9}
.sa .an{color:var(--tp)}
.sa .r.ac{padding-right:25px}
.sa .bad{color:var(--error)}
.sa .st{width:15px;height:15px;margin-left:10px;stroke-width:2}
.sa .st.err{color:var(--error);stroke-width:1.8}
.sa .spin{width:13px;height:13px;margin:0 1px 0 11px;border-radius:50%;border:1.8px solid rgba(152,160,168,.25);border-top-color:var(--ts)}
.sa .cv{width:12px;height:12px;margin:0 1.5px 0 11.5px;stroke-width:2.3}
.variants .vcol{width:100%;display:flex;flex-direction:column;gap:6px}
.pcard.task{box-shadow:none}
.pcard.task .h1{color:var(--ts)}
.pcard.task .pt{display:-webkit-box;-webkit-line-clamp:4;-webkit-box-orient:vertical;overflow:hidden}
.hdr .hb.back{left:16px}
.hdr .hb.back .ic{width:15px;height:15px;stroke-width:2.6}
.hdr.subh .ast{left:53px;top:16px;stroke-width:2.1}
.hdr.subh .ttl{left:74px;right:56px}
.hdr.subh .sub{left:53px;right:56px}
.rop{position:absolute;left:50%;bottom:49px;transform:translateX(-50%);height:44px;border-radius:22px;padding:0 20px 0 18px;display:flex;align-items:center;gap:9px;font:400 14px/20px var(--mono);color:var(--ts);white-space:nowrap;z-index:40}
.rop .spin{width:13px;height:13px;border-radius:50%;border:1.8px solid rgba(152,160,168,.25);border-top-color:var(--ts)}
.rop .st{width:15px;height:15px;stroke-width:2}
.t2f{display:flex;align-items:center;height:21px}
.t2f .tx{min-width:0;overflow:hidden;text-overflow:ellipsis}
.sbd{display:inline-flex;align-items:center;gap:4px;height:17.3px;padding:0 7px 0 5.5px;border-radius:5px;background:var(--badgeOk);color:var(--ok);font:600 11px/1 var(--sf);letter-spacing:.1px;margin-right:7px;flex:none}
.sbd .ic{width:11px;height:11px;stroke-width:2.2}
.dlab{display:flex;justify-content:space-between;margin:20.3px 16.3px 7px;font:400 12px/16px var(--sf);letter-spacing:.25px;text-transform:uppercase;color:var(--ts)}
.dlab span+span{text-transform:none;letter-spacing:0}
.sal .rw{display:flex;align-items:center;height:56px;padding:0 16.7px 0 16.3px;gap:12px}
.sal .rw+.rw{border-top:1px solid var(--divider)}
.sal .rw.nest{padding-left:44.3px}
.sal .sx{width:16px;display:grid;place-items:center;flex:none;color:var(--ts)}
.sal .sx .ic{width:16px;height:16px;stroke-width:2}
.sal .sx .ic.err{color:var(--error);stroke-width:1.8}
.sal .spin{width:14px;height:14px;border-radius:50%;border:1.8px solid rgba(152,160,168,.25);border-top-color:var(--ts)}
.sal .c{flex:1;min-width:0}
.sal .t{font:400 15px/20px var(--sf);color:var(--tp);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sal .s{font:400 13px/17px var(--sf);color:var(--ts);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sal .s b{font-weight:400;color:var(--error)}
.sal .cv{width:12px;height:12px;color:var(--ts);stroke-width:2.3;flex:none}
.wf .inner{padding:8px 12px 10px}
.wf .wp{display:flex;align-items:center;height:24px;white-space:nowrap}
.wf .wp .pi{width:13px;height:13px;margin-right:9px;flex:none;stroke-width:2.2}
.wf .wp .pt{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}
.wf .wp .pc{margin-left:10px}
.wf .wp.cur .pt{color:var(--tp);font-weight:700}
.wf .wsp{width:13px;height:13px;margin-right:9px;flex:none;border-radius:50%;border:1.8px solid rgba(152,160,168,.25);border-top-color:var(--ts)}
.wf .pdot{width:11px;height:11px;margin:0 10px 0 1px;flex:none;border-radius:50%;border:1.6px solid var(--sepDot)}
.wf .pd{padding-left:22px;height:18px;font-style:italic;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.wf .ag{display:flex;align-items:center;height:20px;padding-left:22px;white-space:nowrap}
.wf .ag .ai{width:11px;height:11px;margin-right:8px;flex:none;stroke-width:2.3}
.wf .ag .wsp{width:11px;height:11px;margin-right:8px;border-width:1.6px}
.wf .ag .lb{width:64px;flex:none;color:var(--tp)}
.wf .ag .sm{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}
.wf .wm{padding:9px 15px 11px 24px;font:400 12px/16px var(--mono);color:var(--ts);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}

@keyframes spin{to{transform:rotate(360deg)}}
@keyframes pulse{0%,100%{box-shadow:0 0 0 3px rgba(0,255,0,.12),0 0 8px 1px rgba(0,255,0,.25)}50%{box-shadow:0 0 0 6px rgba(0,255,0,.2),0 0 16px 4px rgba(0,255,0,.45)}}
@keyframes astp{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.55;transform:scale(.82)}}
@keyframes blink{0%,49%{opacity:1}50%,100%{opacity:0}}
.ring .rot{transform-box:view-box;transform-origin:20px 20px;animation:spin 1.6s linear infinite}
.stop svg .rot{transform-box:view-box;transform-origin:10px 10px;animation:spin 1.4s linear infinite}
.tool .spin,.camcap .sp{animation:spin .9s linear infinite}
.hdr .dot.pulse{animation:pulse 1.6s ease-in-out infinite}
.dr .ti.pl,.rr .ti.pl{animation:astp 1.4s ease-in-out infinite}
.caret{animation:blink 1.1s step-end infinite}
.sa .spin,.rop .spin,.sal .spin,.wf .wsp{animation:spin .9s linear infinite}
@media (prefers-reduced-motion:reduce){*{animation:none!important}}
"""

SYMBOLS = """
<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>
<symbol id="i-claude" viewBox="0 0 24 24"><path d="%(AST)s"/></symbol>
<symbol id="i-gear" viewBox="0 0 24 24"><path d="%(GEAR)s"/><circle cx="12" cy="12" r="3.3"/></symbol>
<symbol id="i-house" viewBox="0 0 24 24"><path d="M3.5 11 12 3.9l8.5 7.1"/><path d="M5.8 9.3V20h4.6v-5.7h3.2V20h4.6V9.3"/></symbol>
<symbol id="i-sidebar" viewBox="0 0 24 24"><rect x="3" y="4.5" width="18" height="15" rx="3.3"/><path d="M9.3 4.5v15M5.7 8.4h1.2M5.7 11.2h1.2M5.7 14h1.2"/></symbol>
<symbol id="i-chev-r" viewBox="0 0 24 24"><path d="M8.5 4.5 16 12l-7.5 7.5"/></symbol>
<symbol id="i-chev-d" viewBox="0 0 24 24"><path d="M4.5 8.5 12 16l7.5-7.5"/></symbol>
<symbol id="i-x" viewBox="0 0 24 24"><path d="M5.5 5.5l13 13M18.5 5.5l-13 13"/></symbol>
<symbol id="i-term" viewBox="0 0 24 24"><path d="M3.5 6.2 9.3 12l-5.8 5.8"/><path d="M11.8 18.3h8.7"/></symbol>
<symbol id="i-up" viewBox="0 0 24 24"><path d="M12 20V4.5M5 11.5 12 4.5l7 7"/></symbol>
<symbol id="i-down-line" viewBox="0 0 24 24"><path d="M12 3.2v12.6M6 10l6 6 6-6M4.8 20.6h14.4"/></symbol>
<symbol id="i-plus" viewBox="0 0 24 24"><path d="M12 4v16M4 12h16"/></symbol>
<symbol id="i-mic" viewBox="0 0 24 24"><rect x="8.7" y="2.7" width="6.6" height="11.8" rx="3.3"/><path d="M5.3 10.9a6.7 6.7 0 0 0 13.4 0M12 17.6v3.8"/></symbol>
<symbol id="i-redo" viewBox="0 0 24 24"><path d="M4 16.2a8.2 8.2 0 0 1 15.3-4.4"/><path d="M20.3 6.6v5.8h-5.8"/><circle cx="12" cy="17.3" r="1.35" class="fill"/></symbol>
<symbol id="i-search" viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.8"/><path d="M15.6 15.6 20.5 20.5"/></symbol>
<symbol id="i-clock" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.8"/><path d="M12 7v5.3l3.3 2"/></symbol>
<symbol id="i-listrect" viewBox="0 0 24 24"><rect x="3.5" y="3.8" width="5.2" height="5.2" rx="1.2"/><rect x="3.5" y="10.9" width="5.2" height="5.2" rx="1.2"/><rect x="3.5" y="18" width="5.2" height="2.6" rx="1"/><path d="M12 5.2h8.5M12 7.8h5.5M12 12.3h8.5M12 14.9h5.5M12 19.3h8.5"/></symbol>
<symbol id="i-branch" viewBox="0 0 24 24"><circle cx="7" cy="18" r="2.5"/><circle cx="17.2" cy="6" r="2.5"/><path d="M7 15.5V3.3"/><path d="M17.2 8.5c0 4.8-10.2 3.2-10.2 7"/></symbol>
<symbol id="i-compass" viewBox="0 0 24 24"><path d="M18.4 5.6 14.6 14.6 5.6 18.4 9.4 9.4z"/></symbol>
<symbol id="i-copy" viewBox="0 0 24 24"><rect x="8.5" y="8.5" width="11.8" height="11.8" rx="2.7"/><path d="M15.5 5.4a2.4 2.4 0 0 0-2.4-2.1H6.1A2.4 2.4 0 0 0 3.7 5.7v7a2.4 2.4 0 0 0 2 2.4"/></symbol>
<symbol id="i-sparkles" viewBox="0 0 24 24"><path d="M9.6 5.3c.6 3.7 2.4 5.5 6.1 6.1-3.7.6-5.5 2.4-6.1 6.1-.6-3.7-2.4-5.5-6.1-6.1 3.7-.6 5.5-2.4 6.1-6.1z"/><path d="M17.6 2.8c.26 1.5 1 2.24 2.5 2.5-1.5.26-2.24 1-2.5 2.5-.26-1.5-1-2.24-2.5-2.5 1.5-.26 2.24-1 2.5-2.5z"/><path d="M17.4 17.2v3.4M15.7 18.9h3.4"/></symbol>
<symbol id="i-check" viewBox="0 0 24 24"><path d="M4.6 12.8 9.4 17.6 19.6 6.8"/></symbol>
<symbol id="i-xcircle" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.9"/><path d="M8.9 8.9l6.2 6.2M15.1 8.9l-6.2 6.2"/></symbol>
<symbol id="i-bell" viewBox="0 0 24 24"><path d="M6 16.3v-5.2a6 6 0 0 1 12 0v5.2l1.6 2H4.4z"/><path d="M10 20.8a2.3 2.3 0 0 0 4 0"/></symbol>
<symbol id="i-qr" viewBox="0 0 24 24"><path d="M3.5 8.2V5.6a2.1 2.1 0 0 1 2.1-2.1h2.6M15.8 3.5h2.6a2.1 2.1 0 0 1 2.1 2.1v2.6M20.5 15.8v2.6a2.1 2.1 0 0 1-2.1 2.1h-2.6M8.2 20.5H5.6a2.1 2.1 0 0 1-2.1-2.1v-2.6"/><rect x="7.2" y="7.2" width="3.8" height="3.8" rx=".6"/><rect x="13" y="7.2" width="3.8" height="3.8" rx=".6"/><rect x="7.2" y="13" width="3.8" height="3.8" rx=".6"/><path d="M13.2 13.2h1.6v1.6M16.8 13.6v3.2h-3.4"/></symbol>
<symbol id="i-link" viewBox="0 0 24 24"><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1.2 1.2"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1.2-1.2"/></symbol>
<symbol id="i-doc" viewBox="0 0 24 24"><path d="M6.6 3.4h7l4.8 4.8v11a1.6 1.6 0 0 1-1.6 1.6H6.6A1.6 1.6 0 0 1 5 19.2V5a1.6 1.6 0 0 1 1.6-1.6z"/><path d="M13.4 3.6v4.8h4.8M8.4 12.8h7M8.4 16.2h4.6"/></symbol>
<symbol id="i-pencil" viewBox="0 0 24 24"><path d="M15.3 4.6l4.1 4.1L8.6 19.5 3.8 20.2l.7-4.8z"/><path d="M13.4 6.5l4.1 4.1"/></symbol>
<symbol id="i-agent" viewBox="0 0 24 24"><rect x="3.5" y="3.5" width="7.2" height="7.2" rx="1.9"/><rect x="13.3" y="13.3" width="7.2" height="7.2" rx="1.9"/><path d="M7.1 10.7v3.5a2.9 2.9 0 0 0 2.9 2.9h3.3"/></symbol>
<symbol id="i-laptop" viewBox="0 0 24 24"><rect x="4.5" y="5" width="15" height="10.6" rx="1.7"/><path d="M2.4 18.8h19.2"/></symbol>
<symbol id="i-warn" viewBox="0 0 24 24"><path d="M10.4 4.6a1.8 1.8 0 0 1 3.2 0l7.3 13a1.8 1.8 0 0 1-1.6 2.7H4.7a1.8 1.8 0 0 1-1.6-2.7z"/><path d="M12 9.6v4.6"/><circle cx="12" cy="17" r=".9" class="fill"/></symbol>
<symbol id="i-excl" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.9"/><path d="M12 7.4v5.8"/><circle cx="12" cy="16.4" r=".95" class="fill"/></symbol>
<symbol id="i-q" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.9"/><path d="M9.5 9.7a2.6 2.6 0 1 1 3.7 2.4c-.8.4-1.2 1-1.2 1.8v.4"/><circle cx="12" cy="16.9" r=".95" class="fill"/></symbol>
<symbol id="i-compress" viewBox="0 0 24 24"><path d="M4 14h6v6M20 10h-6V4M10 14l-6.2 6.2M14 10l6.2-6.2"/></symbol>
<symbol id="i-trash" viewBox="0 0 24 24"><path d="M4.3 6.4h15.4M9.4 6.4V4.2h5.2v2.2M6.3 6.4l1 13.4h9.4l1-13.4M10 10.4v5.6M14 10.4v5.6"/></symbol>
<symbol id="i-pie" viewBox="0 0 24 24"><path d="M11 4.1a8.4 8.4 0 1 0 8.9 8.9H11z"/><path d="M14 2.9v7.1h7.1A7.3 7.3 0 0 0 14 2.9z"/></symbol>
<symbol id="i-dollar" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.9"/><path d="M14.7 9.3c-.3-1.1-1.4-1.8-2.7-1.8-1.5 0-2.7.8-2.7 2 0 2.8 5.5 1.4 5.5 4.3 0 1.2-1.2 2.1-2.8 2.1-1.4 0-2.6-.7-2.9-1.9M12 5.9v1.6M12 16v1.8"/></symbol>
<symbol id="i-stopc" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.9"/><rect x="8.9" y="8.9" width="6.2" height="6.2" rx="1.3" class="fill"/></symbol>
<symbol id="i-globe" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.6 3.7 5.6 3.7 9S14.5 18.4 12 21c-2.5-2.6-3.7-5.6-3.7-9S9.5 5.6 12 3z"/></symbol>
<symbol id="i-shift" viewBox="0 0 24 24"><path d="M12 3.8 3.8 12.6h4.5v7.2h7.4v-7.2h4.5z"/></symbol>
<symbol id="i-del" viewBox="0 0 24 24"><path d="M8.6 5.2h11a1.8 1.8 0 0 1 1.8 1.8v10a1.8 1.8 0 0 1-1.8 1.8h-11L2.4 12z"/><path d="M11.6 9.3l5.4 5.4M17 9.3l-5.4 5.4"/></symbol>
<symbol id="i-return" viewBox="0 0 24 24"><path d="M19.6 5.8v5.6a2.2 2.2 0 0 1-2.2 2.2H5"/><path d="M9.3 9.3 5 13.6l4.3 4.3"/></symbol>
<symbol id="i-emoji" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><circle cx="9" cy="10" r="1.1" class="fill"/><circle cx="15" cy="10" r="1.1" class="fill"/><path d="M8 14.2a4.7 4.7 0 0 0 8 0"/></symbol>
<symbol id="i-lock" viewBox="0 0 24 24"><rect x="4.8" y="10.2" width="14.4" height="11" rx="2.6" class="fill"/><path d="M8 10.2V7.6a4 4 0 0 1 8 0v2.6"/></symbol>
<symbol id="i-flash" viewBox="0 0 24 24"><path d="M8.2 3.2h7.6v3.2l-2 3.4v11H10.2v-11l-2-3.4z"/><path d="M8.2 6.4h7.6"/></symbol>
<symbol id="i-camera" viewBox="0 0 24 24"><path d="M3.8 8.6a2 2 0 0 1 2-2h2.1L9.4 4.4h5.2l1.5 2.2h2.1a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5.8a2 2 0 0 1-2-2z"/><circle cx="12" cy="13" r="3.7"/></symbol>
<symbol id="i-cmd" viewBox="0 0 24 24"><path d="M9 9V6.5A2.5 2.5 0 1 0 6.5 9h11A2.5 2.5 0 1 0 15 6.5v11a2.5 2.5 0 1 0 2.5-2.5h-11A2.5 2.5 0 1 0 9 17.5z"/></symbol>
<symbol id="i-clip" viewBox="0 0 24 24"><rect x="5.5" y="4.6" width="13" height="16" rx="2.3"/><rect x="9" y="3" width="6" height="3.3" rx="1.1"/></symbol>
<symbol id="i-history" viewBox="0 0 24 24"><path d="M4.4 12a7.6 7.6 0 1 0 2.3-5.4L4.4 8.9"/><path d="M4.4 4.4v4.5h4.5"/><path d="M12 8v4.4l2.9 1.7"/></symbol>
<symbol id="i-kbdx" viewBox="0 0 24 24"><rect x="2.5" y="5.2" width="19" height="12.2" rx="2.1"/><path d="M6 9.2h.01M9 9.2h.01M12 9.2h.01M15 9.2h.01M18 9.2h.01M7.6 13.4h8.8"/><path d="M3.5 2.8 20.5 21"/></symbol>
<symbol id="i-cup" viewBox="0 0 24 24"><path d="M4.6 10.4h11.6v4.2a4.8 4.8 0 0 1-4.8 4.8H9.4a4.8 4.8 0 0 1-4.8-4.8z"/><path d="M16.2 11.6h1.3a2.4 2.4 0 0 1 0 4.8h-1.6"/><path d="M3.4 21.2h14.2"/><path d="M10.4 2.6v5M8 3.6l4.8 3M8 6.6l4.8-3M7.9 5.1h5"/></symbol>
<symbol id="i-bolt" viewBox="0 0 10 10"><path d="M6 1.3 2.9 5.6h2.1L4.1 8.7 7.2 4.4H5.1z" class="fill"/></symbol>
<symbol id="i-send-arrow" viewBox="0 0 24 24"><path d="M12 19.5V5M5.8 11.2 12 5l6.2 6.2"/></symbol>
<symbol id="i-ast6" viewBox="0 0 24 24"><path d="M12 2.5v19M3.8 7.2l16.4 9.6M3.8 16.8l16.4-9.6"/></symbol>
<symbol id="i-refresh" viewBox="0 0 24 24"><path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3"/><path d="M19.7 3.9v4.4h-4.4"/></symbol>
<symbol id="i-chev-l" viewBox="0 0 24 24"><path d="M15.5 4.5 8 12l7.5 7.5"/></symbol>
<symbol id="i-flow" viewBox="0 0 24 24"><rect x="3.5" y="3.5" width="6" height="6" rx="1.6"/><rect x="14.5" y="9" width="6" height="6" rx="1.6"/><rect x="3.5" y="14.5" width="6" height="6" rx="1.6"/><path d="M9.5 6.5h2.4a1.6 1.6 0 0 1 1.6 1.6V12h1M9.5 17.5h2.4a1.6 1.6 0 0 0 1.6-1.6V12"/></symbol>
<symbol id="i-wifix" viewBox="0 0 24 24"><path d="M2.8 9.2a13.5 13.5 0 0 1 18.4 0M5.9 12.5a9 9 0 0 1 12.2 0M9 15.8a4.5 4.5 0 0 1 6 0"/><circle cx="12" cy="19.2" r="1.1" class="fill"/><path d="M4 3.5 20 20.5"/></symbol>
</defs></svg>
""" % {'AST': ICONS['AST'], 'GEAR': ICONS['GEAR']}

def I(name, cls=''):
    return f'<svg class="ic {cls}"><use href="#i-{name}"/></svg>'

SIGNAL = '<svg width="19" height="12" viewBox="0 0 19 12"><rect x="0" y="7.6" width="3.2" height="4.4" rx="1" fill="#fff"/><rect x="5.2" y="5.2" width="3.2" height="6.8" rx="1" fill="#fff"/><rect x="10.4" y="2.6" width="3.2" height="9.4" rx="1" fill="#fff"/><rect x="15.6" y="0" width="3.2" height="12" rx="1" fill="#fff"/></svg>'
WIFI = '<svg width="17" height="12" viewBox="0 0 17 12"><path fill="#fff" d="M8.5 2.3c2.5 0 4.8.95 6.5 2.55l1.2-1.25C14.2 1.65 11.5.5 8.5.5S2.8 1.65.8 3.6L2 4.85C3.7 3.25 6 2.3 8.5 2.3zm0 3.45c1.6 0 3.05.6 4.15 1.6l1.2-1.25C12.4 4.75 10.55 4 8.5 4S4.6 4.75 3.15 6.1l1.2 1.25c1.1-1 2.55-1.6 4.15-1.6zm0 3.45c.7 0 1.35.25 1.85.7l1.2-1.25C10.85 7.9 9.75 7.45 8.5 7.45s-2.35.45-3.05 1.2l1.2 1.25c.5-.45 1.15-.7 1.85-.7zm0 2.8 1.25-1.3c-.33-.3-.77-.48-1.25-.48s-.92.18-1.25.48z"/></svg>'
BATT = '<svg width="27" height="13" viewBox="0 0 27 13"><rect x=".5" y=".5" width="23.5" height="12" rx="3.8" fill="none" stroke="#fff" stroke-opacity=".4"/><rect x="2.3" y="2.3" width="17.4" height="8.4" rx="2.2" fill="#fff"/><path d="M25.3 4.4v4.2c.8-.3 1.4-1.1 1.4-2.1s-.6-1.8-1.4-2.1z" fill="#fff" fill-opacity=".45"/></svg>'

def sb(time='9:41', lock=False):
    t = '' if lock else f'<div class="t">{time}</div>'
    car = '<div class="lk-car">Vivo</div>' if lock else ''
    return f'<div class="sb">{t}<div class="ics">{SIGNAL}{WIFI}{BATT}</div></div>{car}'

HI = '<div class="hi"></div>'

C = 2 * math.pi * 18.5

def ring(value, kind):
    track = '<circle cx="20" cy="20" r="18.5" fill="none" stroke="var(--ringTrack)" stroke-width="3"/>'
    arc = ''
    badge = ''
    if kind == 'work':
        L = 0.07 * C
        arc = f'<g class="rot"><circle cx="20" cy="20" r="18.5" fill="none" stroke="var(--ok)" stroke-width="3" stroke-linecap="round" stroke-dasharray="{L:.2f} {C:.2f}" stroke-dashoffset="{-0.095*C:.2f}" transform="rotate(-90 20 20)"/></g>'
    else:
        color = {'done': 'var(--ok)', 'warn': 'var(--dirty)', 'arch': 'rgba(0,255,0,.28)', 'off': '#4A4E54'}[kind]
        L = value / 100 * C
        arc = f'<circle cx="20" cy="20" r="18.5" fill="none" stroke="{color}" stroke-width="3" stroke-linecap="round" stroke-dasharray="{L:.2f} {C:.2f}" transform="rotate(-90 20 20)"/>'
    if kind in ('work', 'done'):
        badge = '<circle cx="20" cy="1.5" r="5.2" fill="var(--ok)"/><use href="#i-bolt" x="15" y="-3.5" width="10" height="10" color="#000"/>'
    elif kind == 'warn':
        badge = '<circle cx="20" cy="1.5" r="5.2" fill="var(--dirty)"/><rect x="19.3" y="-1.6" width="1.4" height="3.7" rx=".7" fill="#1a1206"/><circle cx="20" cy="3.6" r=".8" fill="#1a1206"/>'
    elif kind == 'off':
        badge = '<circle cx="20" cy="1.5" r="5.2" fill="#4A4E54"/><use href="#i-bolt" x="15" y="-3.5" width="10" height="10" color="#101112"/>'
    ncls = 'n d' if kind in ('arch', 'off') else 'n'
    return f'<div class="ring"><svg viewBox="0 0 40 40">{track}{arc}{badge}</svg><div class="{ncls}">{value}</div></div>'

def hcard(title, ws, tm, value, kind, sub=None, subwarn=False, dim=False, warn=False):
    s = f'<div class="t2{" warn" if subwarn else ""}">{sub}</div>' if sub else ''
    badge_style = ''
    if kind == 'off':
        badge_style = ' style="background:#1B1D1F;color:#8C939A"'
    cc_style = ' style="color:#8a6a5e"' if kind == 'off' else ''
    return (f'<div class="hc{" dim" if dim else ""}{" warn" if warn else ""}">{ring(value, kind)}<div class="t1">{title}</div>{s}'
            f'<div class="meta"><span class="badge"{badge_style}>{ws}</span><span class="sep"></span><span class="cc"{cc_style}>Claude Code</span>'
            f'<span class="sep"></span><span class="tm">{tm}</span></div>{I("chev-r", "chev")}</div>')

def tool(icon, name, rest, st='ok', count=None):
    cnt = f' ×{count}' if count else ''
    if st == 'ok':
        s = I('check', 'st')
    elif st == 'err':
        s = I('xcircle', 'st err')
    else:
        s = '<span class="spin"></span>'
    return f'<div class="tool">{I(icon, "ti")}<span class="sm"><span class="nm">{name}</span>{cnt} {rest}</span>{s}</div>'

def tools(*items):
    return '<div class="tools">' + ''.join(items) + '</div>'

def header(title, sub, dot='', ttl_style=''):
    return (f'<div class="hdr gl gl-chat"><div class="dot {dot}"></div>{I("claude", "ast")}'
            f'<div class="ttl"{ttl_style}>{title}</div><div class="sub">{sub}</div>'
            f'<div class="hb git">{I("branch")}</div><div class="hb nav">{I("compass")}</div></div>')

def composer(text=None, send_on=False):
    if text:
        return f'<div class="cmp gl gl-cmp"><div class="phd draft">{text}</div><div class="sendb on">{I("send-arrow")}</div></div>'
    return f'<div class="cmp gl gl-cmp"><div class="phd">Chat via Mocha…</div><div class="sendb">{I("send-arrow")}</div></div>'

def composer_x(bottom, text_html, act=None):
    ract = ' act' if act == 'redo' else ''
    return (f'<div class="cmpx gl gl-cmp" style="bottom:{bottom}px"><div class="fld">{text_html}</div>'
            f'<div class="brow"><div class="bb">{I("plus")}</div><div class="bb{ract}">{I("redo")}</div><div class="sp"></div>'
            f'<div class="bb">{I("mic")}</div><div class="sendb on" style="margin-left:4px">{I("send-arrow")}</div></div></div>')

def keyboard():
    k = []
    def key(x, y, w, content, cls=''):
        k.append(f'<div class="key {cls}" style="left:{x}px;top:{y}px;width:{w}px">{content}</div>')
    r1 = 'qwertyuiop'; r2 = 'asdfghjkl'; r3 = 'zxcvbnm'
    for i, ch in enumerate(r1):
        key(7 + i * 38, 23.7, 32, ch)
    for i, ch in enumerate(r2):
        key(26 + i * 38, 77.7, 32, ch)
    key(7, 132, 42.7, I('shift'))
    for i, ch in enumerate(r3):
        key(64 + i * 38, 132, 32, ch)
    key(340, 132, 42.7, I('del'))
    key(7, 186, 41, '123', 'sm')
    key(55, 186, 41, I('emoji'))
    key(102.7, 186, 184.3, '<span class="pt">PT</span>')
    key(294, 186, 88.7, I('return'))
    k.append(f'<div class="kicon" style="left:28px;top:246px">{I("globe")}</div>')
    k.append(f'<div class="kicon" style="left:333px;top:246px">{I("mic")}</div>')
    return '<div class="kbd">' + ''.join(k) + '</div>'

def screen(sid, cls, inner, style=''):
    st = f' style="{style}"' if style else ''
    return f'<div class="phone"><div class="screen {cls}" id="{sid}" data-shot{st}>{inner}{HI}</div></div>'

PH = {'core': '<span class="ph core">1a-core</span>', 'fin': '<span class="ph fin">1a-final</span>',
      'b': '<span class="ph b">1b</span>', 'f2': '<span class="ph f2">fase 2</span>',
      'sub': '<span class="ph sub">subagentes</span>'}

def shot(title, phases, scr, note, extra=''):
    chips = ''.join(PH[p] for p in phases)
    notes = ''.join(f'<p>{n}</p>' for n in note)
    return f'<section class="shot"><div class="shot-h"><span class="nm">{title}</span>{chips}</div>{scr}<div class="note">{notes}</div>{extra}</section>'

GI=[0]
def group(title, shots):
    GI[0]+=1
    return f'<div class="grp" id="g{GI[0]}"><h2>{title}</h2><div class="row">{"".join(shots)}</div></div>'

LOGO = I('cup')

# ---------------------------------------------------------------- 1 Pareamento
def pair_base(extra, cta_top=600, link_top=664):
    return (sb() + f'<div class="logo">{LOGO}</div><h1>Parear com o Mac</h1>'
            '<div class="lead">O Mocha conversa com o <b style="color:#D9DBDF;font-weight:500">mochad</b> no seu Mac pelo Tailscale.</div>'
            '<div class="steps">'
            '<div class="step"><div class="n">1</div><div>No Mac, rode <code>mochad pair</code> no terminal.</div></div>'
            '<div class="step"><div class="n">2</div><div>Toque em <b style="font-weight:600">Ler QR</b> e aponte para o código.</div></div>'
            '<div class="step"><div class="n">3</div><div>O código vale 10 minutos e serve uma vez só.</div></div>'
            '</div>' + extra +
            f'<div class="cta" style="top:{cta_top}px">{I("qr")}Ler QR</div>'
            f'<div class="linkf" style="top:{link_top}px">{I("link")}<span>mocha://pair?url=…</span><div class="pb">Colar</div></div>')

pair1 = screen('s-pair', 'home pair', pair_base(''))
qr_svg = f'<svg viewBox="-2 -2 29 29"><rect x="-2" y="-2" width="29" height="29" fill="#e9eaec"/><path d="{ICONS["QR"]}" fill="#0b0c0e"/></svg>'
pair2 = screen('s-pair-cam', 'cam', sb() +
    f'<div class="xbtn gl gl-black" style="top:55px">{I("x")}</div>'
    '<div class="camtitle">Ler QR do mochad</div><div class="camsub">No Mac: <code>mochad pair</code></div>'
    f'<div class="scr"><div class="tl">$ mochad pair\nEscaneie com o Mocha no iPhone.\nVale por 10 min.</div>{qr_svg}</div>'
    '<div class="ret"><i></i><i></i><i></i><i></i></div>'
    '<div class="camcap gl gl-black" style="top:560px"><span class="sp"></span>Conectando ao MacBook-Pro…</div>')
pair3 = screen('s-pair-err', 'home pair', pair_base(
    f'<div class="errc" style="top:540px">{I("warn")}<div>Código vencido; gere outro com <code>mochad pair</code>.<div class="s">Os códigos valem 10 minutos.</div></div></div>',
    cta_top=652, link_top=716).replace('<div class="steps">', '<div class="steps" style="top:366px">'))

# ---------------------------------------------------------------- 2 Home
def home_top(extra_btn='', off=False):
    return (f'<div class="gbtn l gl gl-home">{I("sidebar")}</div>{extra_btn}'
            f'<div class="gbtn r gl gl-home">{I("gear")}</div>')

def upill(p5=12, p7=71, off=False):
    op = ' style="opacity:.45"' if off else ''
    return (f'<div class="upill gl gl-pill"><div class="h"{op}>{I("claude", "ast")}<span class="lb">5h</span><span class="bar"><i style="width:{p5}%"></i></span><span class="pc">{p5}%</span></div>'
            f'<div class="dv"></div><div class="h"{op}><span class="lb">7d</span><span class="bar"><i style="width:{p7}%"></i></span><span class="pc">{p7}%</span></div></div>')

def home_list(off=False):
    k = lambda x: 'off' if off else x
    return ('<div class="list">'
        '<div class="sec">Precisa de você</div>'
        + hcard('Posso rodar npm run build para validar o feed?', 'site-pessoal', 'há 1 min', 58, k('warn'), sub='Precisa de você · Shell', subwarn=not off, warn=not off)
        + '<div class="sec">Trabalhando</div>'
        + hcard('Você: implementa login com a Apple nesse worktree…', 'login-social', 'agora', 71, k('work'), sub='Shell: swift test --filter AppleSignIn')
        + hcard('Troquei o OFFSET por cursor em ListRecipes. Ag…', 'receitas-api', 'há 2 min', 84, k('work'))
        + '<div class="sec">Concluídos</div>'
        + hcard('Os testes da tela de ajustes passaram. Quer que…', 'demo-app', 'há 6 min', 62, k('done'))
        + hcard('Sessão limpa', 'receitas-api', 'há 4 min', 100, k('done'))
        + '<div class="sec">Arquivados</div>'
        + hcard('Você: cria o worktree login-social a partir da main', 'login-social', 'ontem', 47, 'off' if off else 'arch', sub='Sessão encerrada', dim=True)
        + hcard('Você: revisa o README antes do release', 'demo-app', 'ontem', 90, 'off' if off else 'arch', sub='Sessão encerrada', dim=True)
        + '</div>')

home1 = screen('s-home', 'home', sb() + home_top() + home_list() + upill())
home2 = screen('s-home-off', 'home', sb() + home_top() +
    f'<div class="offcap gl gl-home"><i></i>Sem conexão com o Mac</div>' + home_list(off=True) + upill(off=True))
home3 = screen('s-home-empty', 'home', sb() + home_top() +
    f'<div class="empty"><div class="et">{I("claude")}</div><h3>Nenhum Claude aberto</h3>'
    '<p>Quando você abrir o Claude Code num workspace do Herdr no Mac, ele aparece aqui.</p>'
    f'<div class="eb">{I("sidebar")}Ver workspaces</div></div>' + upill(3, 64))

# ---------------------------------------------------------------- 3 Uso
def ubar(label, pct, reset, pace=None, cls=''):
    b = f'<b style="left:{pace}%"></b>' if pace is not None else ''
    return f'<div class="br"><span class="l">{label}</span><span class="bt"><i style="width:{pct}%"></i>{b}</span><span class="p">{pct}%</span><span class="r">{reset}</span></div>'

uso = screen('s-uso', 'home', sb() + home_top() + home_list() +
    '<div class="sheet"><div class="grab"></div><h3>Uso</h3><div class="upd">atualizado há 4 min</div>'
    f'<div class="ucard"><div class="uhd"><div class="tile">{I("claude")}</div><div class="tx"><div class="a">Max 20x (d•••@e•••.com)</div>'
    '<div class="b">Claude Code · MacBook</div></div></div><div class="udiv"></div>'
    '<div class="bars">' + ubar('5h', 12, '3h 35m', 28) + ubar('7d', 71, '2d 10h', 94) + '</div>'
    '<div class="pace">5h: ritmo mais lento · 7d: ritmo mais lento</div></div>'
    '<div class="ufoot">Os números vêm do último turno do Claude no Mac e ficam velhos quando não há turnos. O traço cinza marca onde o uso estaria num ritmo constante até o fim da janela.</div>'
    '</div>')

# ---------------------------------------------------------------- 4 Detalhe
def dbar(label, pct, reset):
    return f'<div class="br"><span class="l">{label}</span><span class="bt"><i style="width:{pct}%"></i></span><span class="p">{pct}%</span><span class="r">{reset}</span></div>'

def detail(sid, title, ws, badge_cls, badge_txt, wswarn=False):
    return screen(sid, 'home', sb() +
        '<div class="dsheet"></div><div class="dflow">'
        f'<div class="hero"><div class="ht">{I("claude")}</div><h2>{title}</h2>'
        f'<div class="hm"><span class="w{" warn" if wswarn else ""}">{ws}</span> · MacBook · agora</div>'
        f'<div class="hb"><span class="stb {badge_cls}">{badge_txt}</span></div></div>'
        f'<div class="obtn">{I("term")}Abrir terminal</div>'
        '<div class="dcard acct"><div class="hd"><span>Conta</span><span>Max 20x (d•••@e•••.com)</span></div><div class="rows">'
        + dbar('5h', 12, '3h 35m') + dbar('7d', 71, '2d 10h') + '</div></div>'
        '<div class="dcard dtab">'
        '<div class="tr">Host<span class="v">MacBook</span></div>'
        '<div class="tr">Modelo<span class="v">opus-5-5</span></div>'
        f'<div class="tr">Workspace do Herdr<span class="v m">{ws}</span></div>'
        '<div class="tr">Tab do Herdr<span class="v m">Claude</span></div>'
        f'<div class="tr">Sessão<span class="v m">b3e8d1f0-2c4a…7a5c3e2b0d9f{I("copy")}</span></div>'
        '</div></div>'
        f'<div class="xbtn gl gl-hero">{I("x")}</div><div class="scrollind"></div>')

det1 = detail('s-det', 'Você: implementa login com a Apple nesse worktree. usa AuthenticationServices e guarda a sessão no Keychain', 'login-social', 'work', 'TRABALHANDO')
det2 = detail('s-det-need', 'Posso rodar npm run build para validar o feed RSS antes do commit?', 'site-pessoal', 'need', 'PRECISA DE VOCÊ', wswarn=True)
det_variants = ('<div class="variants"><div class="cap">Variantes do selo (a borda de TRABALHANDO gira; as falhas no traço são a animação):</div>'
    '<span class="stb work">TRABALHANDO</span><span class="stb ready">PRONTO</span><span class="stb need">PRECISA DE VOCÊ</span></div>')


EARLY_LOGIN = ('<div class="p">Li o <span class="ci">AuthService</span> atual: ele só tem login por e-mail. Vou criar um coordinator separado para a Apple e plugar no mesmo <span class="ci">SessionStore</span>.</div>'
    + tools(tool('doc', 'Read', 'Auth/AuthService.swift', count=2), tool('pencil', 'Edit', 'DemoApp.entitlements'),
            tool('pencil', 'Write', 'Auth/AppleSignInCoordinator.swift'), tool('term', 'Shell', 'xcodebuild -scheme DemoApp build'))
    + '<div class="p">Build limpo. Agora os testes:</div>'
    + tools(tool('term', 'Shell', 'swift test --filter AppleSignIn', count=2)))
EARLY_RECEITAS = ('<div class="p">A listagem usa <span class="ci">LIMIT/OFFSET</span>; com 40 mil receitas a página 200 leva 1,8 s. Cursor resolve sem mudar o contrato.</div>'
    + tools(tool('term', 'Shell', 'rg -n "OFFSET" internal/', count=2), tool('doc', 'Read', 'internal/recipes/handler.go'))
    + '<div class="p">Vou usar um cursor opaco em base64 com ordenação estável por id.</div>')
EARLY_SITE = ('<div class="ub">adiciona modo escuro com toggle e um feed RSS com os posts</div>'
    + '<div class="think">Pensou</div>'
    + tools(tool('doc', 'Read', 'src/layouts/Base.astro', count=3), tool('term', 'Shell', 'ls src/content/posts | head'))
    + '<div class="p">O site já tem variáveis de cor em <span class="ci">theme.css</span>; o modo escuro vira um segundo conjunto delas.</div>')

# ---------------------------------------------------------------- 5 Chat conversa
CHAT_HDR = header('Login com a Apple', 'login-social • opus-5-5 • feat/login-social')

chat_a = screen('s-chat-a', '', sb() +
    '<div class="chat" style="top:122px">'
    '<div class="chip"><span>/clear</span></div>'
    '<div class="notice">Sessão nova · 13:44 · opus-5-5</div>'
    '<div class="ub">implementa login com a Apple nesse worktree. usa AuthenticationServices e guarda a sessão no Keychain</div>'
    '<div class="think">Pensou: Preciso entender o AuthService atual antes. E o entitlement de Sign in with Apple…</div>'
    + tools(tool('doc', 'Read', 'Auth/AuthService.swift', count=2),
            tool('pencil', 'Edit', 'DemoApp.entitlements'),
            tool('term', 'Shell', "xcodebuild -scheme DemoApp -destination 'generic/platform=iOS'", st='err', count=3))
    + '<div class="p">O build falhou: faltam os métodos de <span class="ci">ASAuthorizationControllerDelegate</span>, que precisam ser <span class="ci">nonisolated</span>. Corrigindo.</div>'
    + tools(tool('pencil', 'Edit', 'Auth/AppleSignInCoordinator.swift'),
            tool('term', 'Shell', "xcodebuild -scheme DemoApp build"))
    + '<div class="p">Build limpo. Agora os testes:</div>'
    + tools(tool('term', 'Shell', 'swift test --filter AppleSignIn'))
    + '<div class="p">Os 6 testes passaram, inclusive o de token expirado.</div>'
    '</div>' + CHAT_HDR + composer())

chat_b = screen('s-chat-b', '', sb() +
    '<div class="chat" style="bottom:95px">'
    + tools(tool('term', 'Shell', 'xcrun simctl launch booted com.demo.app'), tool('term', 'Shell', 'xcrun simctl io booted screenshot /tmp/login.png')) +
    '<div class="p">Revisei o fluxo inteiro no simulador e o login volta para a Home sem piscar.</div>'
    '<h4>Login com a Apple pronto</h4>'
    '<div class="p">O coordinator usa <span class="ci">ASAuthorizationAppleIDProvider</span> e guarda o token em <span class="ci">KeychainSessionStore</span>.</div>'
    '<ul><li><span class="ci">AppleSignInCoordinator</span> com <b>async/await</b></li>'
    '<li>entitlement <span class="ci">applesignin</span> no target</li><li>6 testes novos, todos passando</li></ul>'
    '<table class="tbl"><tr><th style="width:52%">Arquivo</th><th>Mudança</th></tr>'
    '<tr><td><span class="ci">AppleSignIn­Coordinator</span></td><td>novo</td></tr>'
    '<tr><td><span class="ci">AuthService</span></td><td>signInWithApple()</td></tr>'
    '<tr><td><span class="ci">DemoApp.entitlements</span></td><td>Sign in with Apple</td></tr></table>'
    '<div class="code"><span class="cm">// AuthService.swift</span>\nlet credential = try await coordinator.signIn()\ntry keychain.save(credential.identityToken, for: .appleSession)<div class="fade"></div><div class="sbar"></div></div>'
    '<div class="foot">Brewed for 45s</div>'
    '<div class="recap"><b>Recap:</b> Você pediu login com a Apple no worktree login-social. Está pronto e testado; falta decidir se eu abro o PR.</div>'
    '</div>' + CHAT_HDR + composer())

# ---------------------------------------------------------------- 6 Card expandido
chat_exp = screen('s-chat-exp', '', sb() +
    '<div class="chat" style="top:60px">'
    '<div class="p">de ponta a ponta, sem nenhum mock do Keychain no caminho feliz.</div>'
    '<div class="p">Enquanto a suíte roda, reviso o coordinator.</div>'
    + tools(tool('term', 'Shell', 'swift test --filter AppleSignIn 2>&1 | tail -20', count=2),
            tool('sparkles', 'Background task', 'swift test (exit code 0)'))
    + '<div class="texp" style="margin-bottom:12px">' + tool('term', 'Shell', 'cat /private/tmp/…/b7k2q.output') +
    '<div class="inner"><div class="cmd"><span class="dl">$</span> cat /private/<wbr>tmp/<wbr>claude-501/<wbr>demo-app/<wbr>tasks/<wbr>b7k2q.output</div>'
    '<div class="out">Test Suite \'AppleSignInTests\' started\n✔ signInReturnsCredential() (0.012s)\n✔ signInCancelledThrows() (0.004s)\n✔ tokenIsSavedInKeychain() (0.021s)\n✔ expiredTokenSignsOut() (0.009s)\n✔ 6 tests passed in 0.071s\n\n[exited with code 0]</div></div><div class="pad"></div></div>'
    '<div class="think">Pensou: Todos os testes passaram; falta conferir o entitlement…</div>'
    + tools(tool('term', 'Shell', 'git add -A && git commit -m "feat(auth): sign in with Apple"', count=2))
    + '<div class="p">Login com a Apple está pronto e commitado em <span class="ci">feat/login-social</span>. Quer que eu abra o PR?</div>'
    '</div>' + CHAT_HDR + f'<div class="down gl gl-chat">{I("down-line")}</div>' + composer())

# ---------------------------------------------------------------- 7 Trabalhando
STOP = ('<div class="stop"><svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="8.9" fill="none" stroke="rgba(0,255,0,.18)" stroke-width="2"/>'
        f'<g class="rot"><circle cx="10" cy="10" r="8.9" fill="none" stroke="var(--ok)" stroke-width="2" stroke-linecap="round" stroke-dasharray="{0.72*2*math.pi*8.9:.2f} 60" transform="rotate(-60 10 10)"/></g></svg><i></i></div>')
chat_work = screen('s-chat-work', '', sb() +
    '<div class="chat" style="bottom:95px">'
    '<div class="ub">troca a paginação de /receitas para cursor. mantém o formato da resposta</div>'
    '<div class="think">Pensou</div>' + EARLY_RECEITAS
    + tools(tool('doc', 'Read', 'internal/recipes/store.go', count=2),
            tool('pencil', 'Edit', 'internal/recipes/store.go', count=3))
    + '<div class="p">Troquei o <span class="ci">OFFSET</span> por cursor em <span class="ci">ListRecipes</span> e ajustei o handler. Rodando os testes de integração:</div>'
    + tools(tool('term', 'Shell', 'go test ./internal/... -run Pagination -count=1', st='run'))
    + '<div class="ub pend">quando terminar, roda também o golangci-lint</div>'
    f'<div class="pendl">{I("clock")}enviando…</div>'
    f'<div class="status">{I("ast6", "as")}<span>Trabalhando…</span><span class="e">(3m 58s)</span>{STOP}</div>'
    '</div>' + header('Paginação c…/receitas', 'receitas-api • opus-5-5 • development', dot='pulse')
    + composer())

# ---------------------------------------------------------------- 8 Digitando
typing_text = 'agora adiciona um teste para quando o usuário cancela o login no meio<span class="caret"></span>'
chat_type = screen('s-chat-type', '', sb() +
    '<div class="chat" style="bottom:417px">' + EARLY_LOGIN +
    '<div class="p">O login volta para a Home sem piscar e a sessão sobrevive a um relaunch.</div>'
    '<div class="p">Os 6 testes passaram, inclusive o de token expirado.</div>'
    '<div class="foot">Brewed for 45s</div>'
    '<div class="recap"><b>Recap:</b> Você pediu login com a Apple no worktree login-social. Está pronto e testado.</div>'
    '</div>' + CHAT_HDR + composer_x(308, typing_text) + keyboard())

# ---------------------------------------------------------------- 9 Menu
menu = ('<div class="menu" style="bottom:405px">'
    f'<div class="mi">{I("compress")}<div><div class="l">/compact</div><div class="d">Resumir a conversa</div></div></div>'
    f'<div class="mi">{I("trash")}<div><div class="l">/clear</div><div class="d">Começar do zero</div></div></div>'
    f'<div class="mi">{I("pie")}<div><div class="l">/context</div><div class="d">Uso da janela de contexto</div></div></div>'
    f'<div class="mi">{I("dollar")}<div><div class="l">/cost</div><div class="d">Custo e tokens da sessão</div></div></div>'
    '<div class="msep"></div>'
    f'<div class="mi red">{I("stopc")}<div><div class="l">Interromper (Esc)</div></div></div>'
    '</div>')
chat_menu = screen('s-chat-menu', '', sb() +
    '<div class="chat" style="bottom:397px">' + EARLY_LOGIN +
    '<div class="p">O login volta para a Home sem piscar e a sessão sobrevive a um relaunch.</div>'
    '<div class="p">Os 6 testes passaram, inclusive o de token expirado.</div>'
    '<div class="foot">Brewed for 45s</div>'
    '</div>' + CHAT_HDR + composer_x(308, '<span style="color:var(--ts)">Chat via Mocha…</span><span class="caret"></span>', act='redo') + keyboard() + menu)
chat_clear = screen('s-chat-clear', '', sb() +
    '<div class="chat" style="bottom:95px">' + '<div class="ub">implementa login com a Apple nesse worktree. usa AuthenticationServices e guarda a sessão no Keychain</div>' + EARLY_LOGIN +
    '<div class="p">O login volta para a Home sem piscar e a sessão sobrevive a um relaunch.</div>'
    '<div class="p">Os 6 testes passaram, inclusive o de token expirado.</div>'
    '<div class="foot">Brewed for 45s</div>'
    '<div class="recap"><b>Recap:</b> Você pediu login com a Apple no worktree login-social. Está pronto e testado; falta decidir se eu abro o PR.</div>'
    '</div>' + CHAT_HDR + composer() +
    '<div class="scrimf"></div><div class="alert"><h5>Limpar a conversa?</h5>'
    '<p>O Claude começa uma sessão nova nesta tab do Herdr. O histórico atual continua salvo no Mac.</p>'
    '<div class="ab"><div>Cancelar</div><div class="red">Limpar</div></div></div>')

# ---------------------------------------------------------------- 10 Pendentes no chat
SITE_HDR = header('Modo escuro e RSS', 'site-pessoal • opus-5-5 • main', dot='warn')
chat_perm = screen('s-chat-perm', '', sb() +
    '<div class="chat" style="bottom:95px">' + EARLY_SITE +
    '<div class="p">O layout novo já respeita <span class="ci">prefers-color-scheme</span> e o toggle guarda a escolha.</div>'
    + tools(tool('pencil', 'Edit', 'src/layouts/Base.astro', count=2), tool('doc', 'Write', 'src/pages/feed.xml.ts'))
    + '<div class="p">O feed está pronto. Antes do commit quero validar o build completo.</div>'
    f'<div class="pcard"><div class="h1">{I("excl")}Precisa de você<span class="tm">há 12 s</span></div>'
    '<div class="pt"><b>Shell</b> <span class="ts">quer rodar</span></div>'
    '<div class="inner"><span class="c"><span style="color:var(--link)">$</span> npm run build</span><br>cwd: ~/projects/site-pessoal</div>'
    f'<div class="more">{I("chev-d")}Ver entrada completa</div>'
    '<div class="pbtns"><div class="no">Negar</div><div class="yes">Permitir</div></div></div>'
    '</div>' + SITE_HDR + composer())
chat_q = screen('s-chat-q', '', sb() +
    '<div class="chat" style="bottom:95px">' + EARLY_SITE
    + tools(tool('pencil', 'Edit', 'src/styles/theme.css', count=2), tool('term', 'Shell', 'npm run check')) +
    '<div class="p">O layout novo já respeita <span class="ci">prefers-color-scheme</span>.</div>'
    f'<div class="pcard"><div class="h1">{I("q")}Pergunta do Claude<span class="tm">há 40 s</span></div>'
    '<div class="pt">Qual formato de feed você quer publicar?</div>'
    '<div class="opts">'
    '<div class="opt"><span class="rd"></span><div><div class="ol">RSS 2.0</div><div class="od">O mais compatível com leitores antigos</div></div></div>'
    '<div class="opt sel"><span class="rd on"></span><div><div class="ol">Atom</div><div class="od">Datas e ids mais rígidos</div></div></div>'
    '<div class="opt"><span class="rd"></span><div><div class="ol">Os dois</div><div class="od">/feed.xml e /atom.xml</div></div></div>'
    '</div><div class="other">Outro…</div>'
    '<div class="pbtns"><div class="ans">Responder</div></div></div>'
    '</div>' + SITE_HDR + composer())

# ---------------------------------------------------------------- 11 Gaveta
ADD = f'<span class="add">{I("plus")}</span>'

def trow(level, kind, text, sel=False, extra='', pulse=False, dot=False):
    base = 9.7 + 17.3 * level
    cls = 'dr sel' if sel else 'dr'
    if kind == 'ws':
        return (f'<div class="{cls}">{I("chev-d", "cv").replace("<svg", f"<svg style=\"left:{base:.1f}px\"")}'
                f'<span class="wn" style="margin-left:{base + 17.6:.1f}px">{text}</span>{extra}{ADD}</div>')
    if kind == 'wsc':
        return (f'<div class="{cls}">{I("chev-r", "cv").replace("<svg", f"<svg style=\"left:{base:.1f}px\"")}'
                f'<span class="wn" style="margin-left:{base + 17.6:.1f}px">{text}</span>{extra}{ADD}</div>')
    ic = I('claude', 'ti cl' + (' pl' if pulse else '')) if kind == 'cl' else I('term', 'ti sh')
    ic = ic.replace('<svg', f'<svg style="left:{base + 17:.1f}px"')
    bd = '<span class="bd"></span>' if dot else ''
    return f'<div class="{cls}">{ic}<span class="tx" style="margin-left:{base + 38.6:.1f}px;padding-right:28px">{text}</span>{bd}</div>'

def brn(name, dirty=False):
    d = '<span class="dy">*</span>' if dirty else ''
    return f'<span class="br2">{I("branch")}{name}</span>{d}'

def drawer_top(mode):
    a = ' class="on"' if mode == 'rec' else ''
    b = ' class="on"' if mode == 'tree' else ''
    return (f'<div class="dtop"><div class="srch">{I("search")}<span>Buscar workspaces, agentes…</span></div>'
            f'<div class="seg"><div{a}>{I("clock")}</div><div{b}>{I("listrect")}</div></div><div class="dgear">{I("gear")}</div></div>')

tree = ('<div class="tree">'
    + trow(0, 'ws', 'demo-app', extra=brn('main', True))
    + trow(0, 'cl', 'Testes e tela de ajustes')
    + trow(0, 'sh', 'zsh')
    + trow(1, 'ws', 'login-social', extra=brn('feat/login-social', True))
    + trow(1, 'cl', 'Login com a Apple', sel=True, pulse=True)
    + trow(0, 'ws', 'site-pessoal', extra=brn('main'))
    + trow(0, 'cl', 'Modo escuro e RSS', dot=True)
    + trow(0, 'sh', 'npm run dev')
    + trow(0, 'ws', 'receitas-api', extra=brn('development'))
    + trow(0, 'cl', 'Paginação com cursor em /receitas', pulse=True)
    + trow(0, 'cl', 'Sessão limpa')
    + trow(0, 'sh', 'go run ./cmd/api')
    + trow(0, 'sh', 'psql')
    + trow(0, 'wsc', 'anotacoes')
    + '</div>')

chat_under = ('<div class="chat" style="bottom:95px">' + '<div class="ub">implementa login com a Apple nesse worktree. usa AuthenticationServices e guarda a sessão no Keychain</div>' + EARLY_LOGIN +
    '<div class="p">Os 6 testes passaram, inclusive o de token expirado. Agora reviso o fluxo no simulador de ponta a ponta.</div>'
    + tools(tool('term', 'Shell', 'xcrun simctl launch booted com.demo.app'), tool('term', 'Shell', 'xcrun simctl io booted screenshot'))
    + '<div class="p">O login volta para a Home sem piscar e a sessão sobrevive a um relaunch.</div>'
    '<div class="foot">Brewed for 45s</div></div>' + CHAT_HDR + composer())

drawer1 = screen('s-drawer', '', sb() + chat_under + '<div class="scrim"></div><div class="drawer">'
    + drawer_top('tree') + '<div class="dsec">WORKSPACES</div>' + tree + '</div>')

def rrow(title, sub, pulse=False, dot=False, sel=False):
    return (f'<div class="rr{" sel" if sel else ""}">{I("claude", "ti" + (" pl" if pulse else ""))}<div class="c"><div class="t">{title}</div>'
            f'<div class="s">{sub}</div></div>{"<span class=bd></span>" if dot else ""}</div>')

drawer2 = screen('s-drawer-rec', '', sb() + chat_under + '<div class="scrim"></div><div class="drawer">'
    + drawer_top('rec') + '<div class="dsec">RECENTES</div><div class="tree" style="top:136px">'
    + rrow('Login com a Apple', 'login-social · trabalhando · agora', pulse=True, sel=True)
    + rrow('Modo escuro e RSS', 'site-pessoal · precisa de você · há 1 min', dot=True)
    + rrow('Paginação com cursor em /receitas', 'receitas-api · trabalhando · há 2 min', pulse=True)
    + rrow('Testes e tela de ajustes', 'demo-app · há 12 min')
    + rrow('Sessão limpa', 'receitas-api · há 40 min')
    + '</div></div>')

# ---------------------------------------------------------------- 12 Ajustes
settings = screen('s-settings', 'home', sb() + '<div class="dsheet"></div>'
    f'<div class="xbtn gl gl-black" style="top:59px">{I("x")}</div><div class="stitle">Ajustes</div>'
    '<div class="sbody">'
    '<div class="slab">Mac pareado</div><div class="scard">'
    f'<div class="hostrow"><div class="tile">{I("laptop")}</div><div style="flex:1;min-width:0"><div class="a">MacBook-Pro.local</div><div class="b">via Tailscale · pareado em 24/09</div></div></div>'
    '<div class="srow">Conexão<span class="v"><i></i>Conectado</span></div>'
    '<div class="srow">Herdr<span class="v">conectado ao mochad</span></div>'
    '</div><div class="sgap"></div>'
    '<div class="slab">Notificações <span style="letter-spacing:0;text-transform:none">· 1a-final</span></div><div class="scard">'
    '<div class="srow">Turno concluído<span class="tog"></span></div></div>'
    '<div class="sfoot">Avisa quando o Claude termina um turno e o chat dele não está aberto. Pedidos de aprovação sempre avisam.</div>'
    '<div class="sgap"></div>'
    '<div class="slab">Este iPhone</div><div class="scard">'
    '<div class="srow">Perfil de provisionamento<span class="v warn">vence em 5 dias</span></div>'
    '<div class="srow">Versão do app<span class="v m">0.1.0 (14)</span></div>'
    '<div class="srow">Versão do daemon<span class="v m">mochad 0.1.0</span></div></div>'
    '<div class="sgap"></div>'
    '<div class="scard"><div class="srow center">Desparear este iPhone</div></div>'
    '<div class="sfoot">Apaga o token do Keychain e avisa o Mac. Para voltar, rode <span style="font-family:var(--mono);color:var(--link)">mochad pair</span>.</div>'
    '</div>')

# ---------------------------------------------------------------- 13 Inbox
inbox = screen('s-inbox', 'home', sb() + home_top(f'<div class="gbtn r2 gl gl-home">{I("bell")}<span class="bdg">2</span></div>') + home_list()
    + '<div class="sheet" style="top:110px"><div class="grab"></div><h3>Precisa de você <span style="color:var(--ts);font-weight:400">· 2</span></h3>'
    '<div class="chat" style="top:84px;font-size:14.67px">'
    f'<div class="pcard"><div class="h1">{I("excl")}Modo escuro e RSS<span class="tm">site-pessoal · há 12 s</span></div>'
    '<div class="pt"><b>Shell</b> <span class="ts">quer rodar</span></div>'
    '<div class="inner"><span class="c"><span style="color:var(--link)">$</span> npm run build</span></div>'
    f'<div class="more">{I("chev-d")}Ver entrada completa</div>'
    '<div class="pbtns"><div class="no">Negar</div><div class="yes">Permitir</div></div></div>'
    f'<div class="pcard"><div class="h1">{I("q")}Login com a Apple<span class="tm">login-social · há 1 min</span></div>'
    '<div class="pt">Guardo o refresh token no Keychain com acesso após o primeiro desbloqueio?</div>'
    '<div class="opts">'
    '<div class="opt sel"><span class="rd on"></span><div><div class="ol">Sim</div><div class="od">afterFirstUnlock, funciona em background</div></div></div>'
    '<div class="opt"><span class="rd"></span><div><div class="ol">Só com o aparelho desbloqueado</div></div></div>'
    '</div><div class="pbtns"><div class="ans">Responder</div></div></div>'
    '</div></div>')

# ---------------------------------------------------------------- 14 Notificação e Live Activity
lock = screen('s-lock', 'lock', sb(lock=True) +
    f'<div class="lk-lock">{I("lock")}</div><div class="lk-date">sexta-feira, 26 de setembro</div><div class="lk-time">9:41</div>'
    f'<div class="la"><div class="top"><div class="tile">{I("claude")}</div><div><div class="k">2 trabalhando · <em>1 esperando você</em></div><div class="kk">Mocha · MacBook</div></div></div>'
    '<div class="hl"><i></i><div class="c"><div class="a">Modo escuro e RSS</div><div class="b">site-pessoal · Shell: npm run build</div></div><div class="tmr">2:14</div></div></div>'
    f'<div class="nt" style="top:626px"><div class="appic">{LOGO}</div><div class="c"><div class="r1"><div class="a">Claude terminou · receitas-api</div><div class="w">agora</div></div>'
    '<div class="b">Os testes de integração passaram. A paginação agora usa cursor e o formato da resposta não mudou.</div></div></div>'
    f'<div class="lk-btn" style="left:46px">{I("flash")}</div><div class="lk-btn" style="right:46px">{I("camera")}</div>')

banner = screen('s-banner', '', sb() + chat_under +
    f'<div class="nt" style="top:8px;background:rgba(52,52,54,.94)"><div class="appic">{LOGO}</div><div class="c"><div class="r1"><div class="a">Claude precisa de você · site-pessoal</div><div class="w">agora</div></div>'
    '<div class="b">Shell quer rodar npm run build</div></div></div>')

# ---------------------------------------------------------------- 15 Terminal
def tline(top, html):
    return f'<div class="tl" style="top:{top}px">{html}</div>'

TL = 18.6
term_lines = [
    '    sem nenhum mock do Keychain no',
    '    caminho feliz.',
    '',
    '  Login com a Apple está pronto e commitado',
    '  em <span class="lk">feat/login-social</span>.',
    '',
    '<span class="s">✻ Baked for 45s · done 14:46</span>',
    '',
    '<span class="s">※</span> <span class="b" style="color:#bbb">recap:</span> <span class="i">Você pediu login com a Apple no</span>',
    '  <span class="i">worktree login-social. Está pronto e</span>',
    '  <span class="i">testado; falta decidir se eu abro o PR.</span>',
    '  <span class="i">(disable recaps in /config)</span>',
]
term_html = ''.join(tline(96 + i * TL, l) for i, l in enumerate(term_lines))
terminal = screen('s-term', 'term', sb() +
    '<div class="tsheet"><div class="tgrab"></div>'
    f'<div class="thd"><div class="dot"></div><div class="h">MacBook-Pro.local: login-social</div><div class="mb" style="background:var(--git)">{I("branch")}</div><div class="mb" style="background:#9BA0AA">{I("compass")}</div></div>'
    '<div class="tbar"><div class="l">○ tab Claude: Login com a Apple\nall idle</div><div class="r">switch</div></div>'
    + term_html.replace('top:', 'top:', 1) +
    '<div class="trule" style="top:328px"></div>'
    + tline(336, '<span style="color:#ddd">❯</span> abre o PR<span class="caret" style="background:#ddd;width:8px;height:16px;border-radius:0"></span>') +
    '<div class="trule" style="top:364px"></div>'
    + tline(372, '  <span class="bl">Opus 5.5 (1M context)</span> <span class="s">│</span> <span class="y">login-social</span>')
    + tline(372 + TL, '  <span class="yb">⏵⏵ auto mode on</span> <span class="s">(shift+tab to cycle)</span>')
    + '</div>'
    '<div class="acc gl gl-chat">'
    '<div class="k">Ctrl</div><div class="k">Esc</div><div class="k">Tab</div>'
    f'<div class="k">{I("cmd")}</div><div class="k">{I("redo")}</div><div class="k">{I("clip")}</div>'
    f'<div class="grp2"><div class="k g">{I("history")}</div><div class="k g" style="color:#fff">{I("claude")}</div><div class="k g">{I("kbdx")}</div></div>'
    '</div>' + keyboard())

# ---------------------------------------------------------------- 16-19 Subagentes e workflows
def sa_state(state):
    if state == 'ok':
        return I('check', 'st')
    if state == 'err':
        return I('xcircle', 'st err')
    if state == 'stop':
        return I('stopc', 'st')
    return '<span class="spin"></span>'

def sa_card(atype, desc, state, meta, act=None):
    rows = f'<div class="r">{I("agent", "ti")}<span class="sm"><span class="nm">{atype}</span> {desc}</span>{sa_state(state)}</div>'
    if act:
        icon, name, rest = act
        rows += f'<div class="r ac"><span class="ind"></span>{I(icon, "ai")}<span class="sm"><span class="an">{name}</span> {rest}</span></div>'
    rows += f'<div class="r"><span class="ind"></span><span class="sm">{meta}</span>{I("chev-r", "cv")}</div>'
    return f'<div class="sa">{rows}</div>'

def sub_header(title, parent):
    return (f'<div class="hdr subh gl gl-chat"><div class="hb back">{I("chev-l")}</div>{I("agent", "ast")}'
            f'<div class="ttl">{title}</div><div class="sub">subagente de {parent}</div>'
            f'<div class="hb nav">{I("compass")}</div></div>')

def task_card(text):
    return (f'<div class="pcard task"><div class="h1">{I("agent")}Tarefa</div>'
            f'<div class="pt">{text}</div><div class="more">{I("chev-d")}Ver tarefa completa</div></div>')

def ro_pill(state):
    if state == 'run':
        return '<div class="rop gl gl-cmp"><span class="spin"></span><span>Rodando · só leitura</span></div>'
    return f'<div class="rop gl gl-cmp">{I("check", "st")}<span>Concluído · só leitura</span></div>'

SA_LOAD_ACT = ('term', 'Shell', 'k6 run --vus 50 --duration 2m load/list-recipes.js')
PARENT_RECEITAS = 'Paginação c…/receitas'

chat_sub = screen('s-chat-sub', '', sb() +
    '<div class="chat" style="bottom:95px">'
    '<div class="ub">procura os outros endpoints que ainda usam OFFSET e roda o teste de carga de /receitas em paralelo</div>'
    '<div class="think">Pensou</div>'
    '<div class="p">Vou dividir em dois subagentes: um mapeia o uso de <span class="ci">OFFSET</span> e o outro roda o teste de carga. Enquanto isso, reviso o handler.</div>'
    + tools(sa_card('Explore', 'Mapear uso de OFFSET', 'ok', '2m 14s • 18 ferramentas'),
            sa_card('general-purpose', 'Teste de carga /receitas', 'run', '3m 51s • 9 ferramentas', act=SA_LOAD_ACT),
            tool('doc', 'Read', 'internal/recipes/handler.go'))
    + '<div class="p">Achei <span class="ci">OFFSET</span> em <span class="ci">/ingredientes</span> e <span class="ci">/autores</span>. Troco os dois pelo mesmo cursor.</div>'
    + tools(tool('pencil', 'Edit', 'internal/ingredients/store.go', count=2),
            tool('term', 'Shell', 'go test ./internal/ingredients -run Cursor', st='run'))
    + f'<div class="status">{I("ast6", "as")}<span>Trabalhando…</span><span class="e">(4m 21s)</span>{STOP}</div>'
    '</div>' + header(PARENT_RECEITAS, 'receitas-api • opus-5-5 • development', dot='pulse')
    + composer())

sa_variants = ('<div class="variants"><div class="cap">Estados do card do subagente (tocar abre o transcript):</div><div class="vcol">'
    + sa_card('general-purpose', 'Teste de carga /receitas', 'run', '3m 51s • 9 ferramentas', act=SA_LOAD_ACT)
    + sa_card('Explore', 'Mapear uso de OFFSET', 'ok', '2m 14s • 18 ferramentas')
    + sa_card('Plan', 'Revisar o índice de receitas', 'err', '<span class="bad">falhou</span> • 48s • 3 ferramentas')
    + sa_card('Explore', 'Medir a consulta com EXPLAIN', 'stop', 'parado • 1m 02s • 6 ferramentas')
    + '</div></div>')

sub_run = screen('s-sub-run', '', sb() +
    '<div class="chat" style="top:122px">'
    '<div class="notice">general-purpose · 13:52 · opus-5-5</div>'
    + task_card('Rode o teste de carga de GET /receitas com o k6 (load/list-recipes.js): 50 usuários por 2 min, primeiro na main e depois em feat/cursor-receitas. Compare o p95 e a taxa de erro das duas rodadas.')
    + '<div class="think">Pensou</div>'
    + tools(sa_card('Explore', 'Achar o script de carga', 'ok', '41s • 5 ferramentas'),
            tool('doc', 'Read', 'load/list-recipes.js'),
            tool('term', 'Shell', 'k6 run --vus 50 --duration 2m load/list-recipes.js', count=3))
    + '<div class="p">Na <span class="ci">main</span>, com OFFSET: p95 de 1,82 s na página 200 e nenhum erro. Agora com o cursor:</div>'
    + tools(tool('term', 'Shell', 'git switch feat/cursor-receitas &amp;&amp; go build ./...', count=2),
            tool('pencil', 'Edit', 'load/list-recipes.js'))
    + '<div class="p">O script agora segue o <span class="ci">next_cursor</span> da resposta em vez de somar o offset.</div>'
    + tools(tool('term', 'Shell', 'k6 run --vus 50 --duration 2m load/list-recipes.js', st='run'))
    + '</div>' + sub_header('Teste de carga /receitas', PARENT_RECEITAS) + ro_pill('run'))

sub_done = screen('s-sub-done', '', sb() +
    '<div class="chat" style="bottom:95px">'
    + task_card('Procure em internal/ os endpoints que ainda paginam com LIMIT/OFFSET. Liste rota, função e arquivo; não edite nada.')
    + tools(tool('term', 'Shell', 'rg -n "OFFSET" internal/', count=6),
            tool('doc', 'Read', 'internal/ingredients/store.go', count=9))
    + '<div class="p">Três arquivos usam <span class="ci">OFFSET</span>. Confiro as rotas no router:</div>'
    + tools(tool('search', 'Grep', 'r.Get\\(', count=2), tool('doc', 'Read', 'internal/api/router.go'))
    + '<h4>Endpoints com OFFSET</h4>'
    '<ul><li><span class="ci">/ingredientes</span>: <span class="ci">ListIngredients</span> em <span class="ci">internal/ingredients/store.go</span></li>'
    '<li><span class="ci">/autores</span>: <span class="ci">ListAuthors</span> em <span class="ci">internal/authors/store.go</span></li></ul>'
    '<div class="p">O <span class="ci">/receitas</span> já usa cursor. Os dois ordenam por <span class="ci">created_at</span>, sem desempate por id.</div>'
    '<div class="foot">Concluído em 2m 14s · 18 ferramentas</div>'
    '</div>' + sub_header('Mapear uso de OFFSET', PARENT_RECEITAS) + ro_pill('ok'))

def sub_line(n, rest=''):
    tx = f'<span class="tx">{rest}</span>' if rest else ''
    return f'<span class="t2f"><span class="sbd">{I("agent")}{n} subagente{"s" if n > 1 else ""}</span>{tx}</span>'

home_sub = screen('s-home-sub', 'home', sb() + home_top() + '<div class="list">'
    '<div class="sec">Precisa de você</div>'
    + hcard('Posso rodar npm run build para validar o feed?', 'site-pessoal', 'há 1 min', 58, 'warn', sub='Precisa de você · Shell', subwarn=True, warn=True)
    + '<div class="sec">Trabalhando</div>'
    + hcard('Achei OFFSET em /ingredientes e /autores. Troco os dois pelo mesmo cursor.', 'receitas-api', 'agora', 79, 'work', sub=sub_line(1, 'Shell: go test ./internal/ingredients -run Cursor'))
    + hcard('Você: implementa login com a Apple nesse worktree…', 'login-social', 'há 1 min', 71, 'work', sub='Shell: swift test --filter AppleSignIn')
    + '<div class="sec">Concluídos</div>'
    + hcard('Ele roda em background; eu aviso quando a revisão terminar.', 'demo-app', 'há 3 min', 66, 'done', sub=sub_line(2))
    + hcard('Sessão limpa', 'receitas-api', 'há 4 min', 100, 'done')
    + '<div class="sec">Arquivados</div>'
    + hcard('Você: cria o worktree login-social a partir da main', 'login-social', 'ontem', 47, 'arch', sub='Sessão encerrada', dim=True)
    + '</div>' + upill())

def sal_row(state, title, sub, nest=False):
    if state == 'run':
        s = '<span class="spin"></span>'
    elif state == 'err':
        s = I('xcircle', 'err')
    else:
        s = I('check')
    return f'<div class="rw{" nest" if nest else ""}"><span class="sx">{s}</span><div class="c"><div class="t">{title}</div><div class="s">{sub}</div></div>{I("chev-r", "cv")}</div>'

det_sub = screen('s-det-sub', 'home', sb() +
    '<div class="dsheet"></div><div class="dflow">'
    f'<div class="hero"><div class="ht">{I("claude")}</div><h2>Achei OFFSET em /ingredientes e /autores. Troco os dois pelo mesmo cursor.</h2>'
    '<div class="hm"><span class="w">receitas-api</span> · MacBook · agora</div>'
    '<div class="hb"><span class="stb work">TRABALHANDO</span></div></div>'
    f'<div class="obtn">{I("term")}Abrir terminal</div>'
    '<div class="dlab"><span>Subagentes</span><span>1 rodando</span></div>'
    '<div class="dcard sal">'
    + sal_row('run', 'Teste de carga /receitas', 'general-purpose · 3m 51s · 9 ferramentas')
    + sal_row('ok', 'Achar o script de carga', 'Explore · 41s · 5 ferramentas', nest=True)
    + sal_row('ok', 'Mapear uso de OFFSET', 'Explore · 2m 14s · 18 ferramentas')
    + sal_row('ok', 'Gerar fixtures de carga', 'general-purpose · 3m 40s · 22 ferramentas')
    + sal_row('err', 'Revisar o índice de receitas', 'Plan · <b>falhou</b> · 48s · 3 ferramentas')
    + '</div>'
    '<div class="dcard acct"><div class="hd"><span>Conta</span><span>Max 20x (d•••@e•••.com)</span></div><div class="rows">'
    + dbar('5h', 12, '3h 35m') + dbar('7d', 71, '2d 10h') + '</div></div>'
    '</div>'
    f'<div class="xbtn gl gl-hero">{I("x")}</div><div class="scrollind" style="height:140px"></div>')

def wf_phase(state, title, count):
    if state == 'ok':
        ic = I('check', 'pi')
    elif state == 'run':
        ic = '<span class="wsp"></span>'
    else:
        ic = '<span class="pdot"></span>'
    cls = ' cur' if state == 'run' else ''
    return f'<div class="wp{cls}">{ic}<span class="pt">{title}</span><span class="pc">{count}</span></div>'

def wf_agent(state, label, rest):
    ic = '<span class="wsp"></span>' if state == 'run' else I('check', 'ai')
    return f'<div class="ag">{ic}<span class="lb">{label}</span><span class="sm">{rest}</span></div>'

wf_card = ('<div class="texp wf" style="margin-bottom:12px">' + tool('flow', 'Workflow', 'auditoria-a11y', st='run') +
    '<div class="inner">'
    + wf_phase('ok', 'Mapear telas', '1 agente')
    + wf_phase('run', 'Corrigir por tela', '2 de 4 agentes')
    + '<div class="pd">uma tela por agente, com testes de UI</div>'
    + wf_agent('run', 'Ajustes', '<span style="color:var(--tp)">Edit</span> SettingsView.swift')
    + wf_agent('run', 'Perfil', '<span style="color:var(--tp)">Read</span> ProfileView.swift')
    + wf_agent('ok', 'Login', '1m 48s')
    + wf_agent('ok', 'Home', '2m 05s')
    + wf_phase('pend', 'Revisar', 'pendente')
    + '</div><div class="wm">6m 12s • 5 agentes • 86 ferramentas</div></div>')

chat_wf = screen('s-chat-wf', '', sb() +
    '<div class="chat" style="bottom:95px">'
    '<div class="p">Os testes da tela de ajustes passaram. Quer que eu rode a auditoria de acessibilidade também?</div>'
    '<div class="foot">Brewed for 1m 12s</div>'
    '<div class="ub">roda o workflow auditoria-a11y em todas as telas do app</div>'
    '<div class="think">Pensou</div>'
    + tools(tool('search', 'Glob', 'Sources/**/*View.swift'))
    + '<div class="p">O app tem 4 telas. O workflow mapeia as telas, corrige cada uma em paralelo e revisa tudo no fim.</div>'
    + wf_card +
    '<div class="p">Ele roda em background; eu aviso quando a revisão terminar.</div>'
    '<div class="foot">Brewed for 18s</div>'
    '</div>' + header('Auditoria a11y', 'demo-app • opus-5-5 • main') + composer())

wf_variants = ('<div class="variants"><div class="cap">Workflow concluído (o card recolhe numa linha; tocar expande as fases):</div><div class="vcol">'
    + tool('flow', 'Workflow', 'auditoria-a11y · 10 agentes') + '</div></div>')

# ---------------------------------------------------------------- page
N = lambda *xs: list(xs)

page = f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mocha · desenho do app</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:ital,wght@0,400;0,500;0,700;1,400;1,700&display=swap" rel="stylesheet">
<style>{CSS}</style></head><body>
{SYMBOLS}
<header class="top" id="pagetop"><h1>Mocha · desenho completo do app</h1>
<div class="lead">iPhone 14 · 390 × 844 pt · iOS 26 · sempre escuro · referência visual: Moshi</div>
<div class="legend">
<div class="it">{PH['core']}o núcleo que abre o chat</div>
<div class="it">{PH['fin']}menu ↻, notificações de turno</div>
<div class="it">{PH['b']}aprovações, perguntas, inbox, voz, imagem, Live Activity</div>
<div class="it">{PH['f2']}terminal</div>
<div class="it">{PH['sub']}subagentes e workflows</div>
</div></header>
"""

page += group('Entrada', [
    shot('1 · Pareamento', ['core'], pair1, N(
        '<b>Primeira execução ou token recusado.</b> "Ler QR" abre a câmera; "Colar" aceita o link <code>mocha://pair?url=…&amp;code=…</code>, que também chega por deep link.',
        'O botão "Colar" só aparece quando a área de transferência tem um link <code>mocha://pair</code>.')),
    shot('1b · Lendo o QR', ['core'], pair2, N(
        'Câmera em tela cheia. Ao reconhecer o QR, os cantos ficam verdes e a pílula mostra "Conectando ao MacBook-Pro…"; pareado, vai direto para a Home.',
        'X volta para a tela anterior.')),
    shot('1c · Erro de pareamento', ['core'], pair3, N(
        'O aviso fica acima do botão até a próxima tentativa. Outras mensagens: "O Mac respondeu, mas o mochad não está rodando" (502), "Sem conexão com o Mac" (timeout) e "Este iPhone não está mais pareado" (<code>unauthorized</code>).')),
])

page += group('Central de agentes', [
    shot('2 · Home, central de agentes', ['core'], home1, N(
        '<b>Tela inicial do app.</b> Seções, nesta ordem: PRECISA DE VOCÊ (agente <code>blocked</code>, card em âmbar); TRABALHANDO (só <code>working</code>); CONCLUÍDOS (turno terminado há menos de 10 min); ARQUIVADOS (turno terminado há mais de 10 min, sessão com mais de 6 h, sessão substituída por <code>/clear</code>, pane fechado ou card arquivado). <b>Arrastar o card para o lado arquiva.</b>',
        'Card: tocar abre o chat; segurar abre o detalhe. Título = última mensagem (ou "Você: …"); a linha cinza é a última ferramenta. O anel mostra o contexto livre (%) e o arco curto gira enquanto trabalha.',
        'Esquerda abre a árvore de workspaces (gaveta); engrenagem abre Ajustes; a pílula abre o Uso.')),
    shot('2b · Home sem conexão', ['core'], home2, N(
        'A lista mostra o último estado conhecido, com anéis parados em cinza. A cápsula no topo abre Ajustes com o motivo. Nada some da tela, e a reconexão é automática.')),
    shot('2c · Home vazia', ['core'], home3, N(
        'Nenhum Claude aberto no Herdr. "Ver workspaces" abre a gaveta. Criar uma tab com Claude pelo iPhone chega na 1b ("+" no workspace).')),
    shot('3 · Uso do plano', ['core'], uso, N(
        'Folha média sobre a Home; arrastar fecha. Barras de 5h e 7d, com % e o tempo até zerar. O traço cinza marca o ritmo constante; a linha de baixo resume o ritmo. Só Claude.', '"Atualizado há X" no topo: os dados vêm de um cache local no Mac, que fica velho quando não há turnos.')),
    shot('4 · Detalhe do agente', ['core', 'f2'], det1, N(
        '<b>Abre tocando no título do header do chat</b> ou segurando um card da Home. X ou arrastar para baixo fecha.',
        '"Abrir terminal" é da fase 2 e fica oculto até lá. Tocar na sessão copia o ID inteiro.'), det_variants),
    shot('4b · Detalhe, precisa de você', ['core'], det2, N(
        'Mesmo layout com o selo âmbar. Na 1b, um botão "Responder" leva ao card do pedido no chat.')),
])

page += group('Chat', [
    shot('5 · Chat, conversa (início do turno)', ['core'], chat_a, N(
        '<b>Header de vidro:</b> disco de status (tocar volta à Home), título (tocar abre o detalhe), git reservado e desabilitado, bússola abre a gaveta. A lista rola por baixo do header e do composer.',
        'Chip <code>/clear</code> e aviso centralizado marcam a sessão nova. Chamadas seguidas da mesma ferramenta viram um card com ×N; ✗ vermelho quando alguma falhou. <b>Composer recolhido: uma linha só.</b>')),
    shot('5b · Chat, conversa (fim do turno)', ['core'], chat_b, N(
        'Markdown: título, lista, tabela com borda, código inline azul e bloco de código com rolagem horizontal (a borda esmaecida e a barrinha indicam que há mais à direita).',
        '"Brewed for 45s" e "Recap:" em itálico cinza fecham o turno.')),
    shot('6 · Card expandido e tarefa em background', ['core'], chat_exp, N(
        'Tocar num card expande: por chamada, <code>$ comando</code> e a prévia do resultado numa caixa interna. Tocar de novo recolhe.',
        'O botão ↓ aparece quando você rolou para cima; itens novos não mexem na posição de leitura.')),
    shot('7 · Chat, trabalhando', ['core'], chat_work, N(
        'Disco pulsando no header e título truncado no meio. A linha de status fica no fim da lista, com o tempo do turno; <b>o botão verde para o agente</b> (Esc).',
        'A bolha enviada fica esmaecida com "enviando…" até o transcript confirmar; depois de 60 s sem par vira "sem confirmação" e o toque a descarta. Enviar sempre leva ao fim da lista, então o ↓ não aparece aqui (ele está na tela 6).')),
    shot('8 · Chat, digitando', ['core', 'fin', 'b'], chat_type, N(
        '<b>Tocar no composer expande:</b> campo multilinha (até 6 linhas, depois rola) e linha de botões: + e microfone (1b), ↻ (1a-final) e enviar.',
        '<b>Rolar a lista, tocar fora, abrir a gaveta ou enviar fecham o teclado</b> e o composer volta a uma linha. Um rascunho não enviado aparece na linha recolhida, em branco, com enviar aceso.')),
    shot('9 · Menu ↻', ['fin'], chat_menu, N(
        'Abre acima do ↻, por cima do teclado. Lista fixa; comandos que abrem seletor no terminal (<code>/model</code>, <code>/resume</code>) ficam de fora. "Interromper" manda Esc.')),
    shot('9b · Confirmação do /clear', ['fin'], chat_clear, N(
        'Só o <code>/clear</code> pede confirmação. Depois dele, o chat reabre na sessão nova, que começa com o chip <code>/clear</code>.')),
    shot('10 · Pedido de aprovação no chat', ['b'], chat_perm, N(
        'O card entra no fim da lista e o disco do header fica âmbar. Permitir e Negar respondem na hora; "Ver entrada completa" abre o JSON do input.')),
    shot('10b · Pergunta no chat', ['b'], chat_q, N(
        'Seleção única com rádio (múltipla usa caixas). "Outro…" vira resposta livre. Com várias perguntas, cada uma tem o seu bloco e há um "Responder" só.')),
])

page += group('Navegação e sistema', [
    shot('11 · Gaveta, árvore', ['core', 'fin'], drawer1, N(
        'Abre pela bússola do chat ou pelo botão da esquerda da Home; <b>ao abrir, fecha o teclado</b>. Fecha tocando no scrim ou arrastando para a esquerda.',
        '<b>O asterisco com brilho pulsa</b> (trabalhando); o ponto âmbar é "precisa de você"; a linha verde é o chat aberto. Worktree fica aninhado sob o repositório. Tocar numa tab de shell mostra "Terminal chega na fase 2".',
        'O <b>+</b> à direita de cada workspace abre uma tab nova com Claude nele. Enquanto o Claude inicia, o + vira o indicador de progresso do iOS; pronto, a gaveta fecha e o chat novo abre.')),
    shot('11b · Gaveta, recentes', ['core'], drawer2, N(
        'Agentes por última atividade, com workspace e estado. A busca filtra por workspace, tab e título nas duas abas.')),
    shot('12 · Ajustes', ['core', 'fin'], settings, N(
        'Folha aberta pela engrenagem da Home (ou da gaveta). O estado da conexão usa as mesmas mensagens do pareamento. O perfil fica âmbar abaixo de 7 dias.',
        '"Desparear" pede confirmação, manda <code>unpair</code>, limpa o Keychain e volta ao pareamento.')),
    shot('13 · Inbox', ['b'], inbox, N(
        'Sino na Home, ao lado da engrenagem, com a contagem. Um cartão por pedido pendente, com agente, workspace e tempo. Tocar no nome do agente abre o chat.')),
    shot('14 · Tela bloqueada: Live Activity e alerta', ['fin', 'b'], lock, N(
        'O iPhone 14 não tem Dynamic Island: a Live Activity (1b) aparece na tela bloqueada, com o destaque mais urgente e o timer desde o início da espera.',
        'O alerta de turno concluído (1a-final) traz o começo da última mensagem. Tocar abre <code>mocha://agent/&lt;paneId&gt;</code>.')),
    shot('14b · Banner com o app aberto', ['fin'], banner, N(
        'Com o app aberto em outro chat, o alerta chega como banner. O do chat visível é suprimido (<code>setForeground</code>).')),
    shot('15 · Terminal', ['f2'], terminal, N(
        'Só desenho. Folha sobre o chat com o terminal real do pane; a barra de teclas (Ctrl, Esc, Tab, ⌘, colar, histórico, atalho do Claude, fechar teclado) fica acima do teclado.')),
])

page += group('Subagentes e workflows', [
    shot('16 · Chat com subagentes', ['sub'], chat_sub, N(
        '<b>Cada chamada de <code>Agent</code> vira um card próprio</b>, sem agrupar com a chamada seguinte: tipo (<code>agentType</code>, sem o prefixo do plugin: <code>feature-dev:code-reviewer</code> vira <code>code-reviewer</code>) em negrito e a descrição. Rodando: a ferramenta atual do subagente, o tempo desde que ele começou e quantas ferramentas ele já chamou. Concluído: ✓ com o tempo e a contagem finais da notificação de tarefa.',
        '<b>Tocar abre o transcript do subagente.</b> O aviso <code>Agent "…" finished</code> que o Claude Code grava no transcript principal não aparece: o card já mostra o fim. Sem tokens no card.'), sa_variants),
    shot('16b · Transcript do subagente, rodando', ['sub'], sub_run, N(
        'Só leitura, por push sobre o chat pai. O header troca o disco por <b>voltar</b> (volta ao chat pai), o asterisco pelo ícone de subagente e mostra "subagente de &lt;título do chat pai&gt;".',
        'O aviso no topo traz o tipo, a hora e o modelo; o card "Tarefa" é o prompt que o Claude principal passou (4 linhas, toque expande). Sem composer e sem linha de status: a pílula diz o estado.')),
    shot('16c · Transcript do subagente, concluído', ['sub'], sub_done, N(
        'O último texto é a resposta que voltou para o Claude principal. A linha final (tempo e ferramentas) vem da notificação de tarefa, não de um <code>turn_duration</code>.',
        'Falha ou parada: a pílula e o card do chat mostram ✗ ou ■, e o motivo da notificação entra como aviso no fim, no texto original (em inglês).')),
    shot('17 · Home com subagentes', ['sub'], home_sub, N(
        'O selo <b>"N subagentes"</b> abre a segunda linha do card enquanto há subagentes rodando naquela sessão (os do <code>Agent</code>, os aninhados e os agentes de workflow). Some quando todos terminam.',
        'O Claude principal pode ter terminado o turno com subagentes em background: o card fica em CONCLUÍDOS com o selo (demo-app).')),
    shot('18 · Detalhe com subagentes', ['sub'], det_sub, N(
        'Lista SUBAGENTES da sessão, logo depois do bloco principal: os que rodam primeiro, depois os terminados do mais recente ao mais antigo. Cada linha: estado, descrição e "tipo · tempo · ferramentas", sem tokens. Um subagente aberto por outro aparece recuado logo abaixo do pai. Tocar abre o transcript.',
        'A folha rola: Conta e a lista de Host, Modelo, Workspace, Tab e Sessão continuam abaixo, como na tela 4.')),
    shot('19 · Chat com workflow', ['sub'], chat_wf, N(
        'Card do <code>Workflow</code> expandido enquanto roda: as fases com ✓ (concluída), giro (atual, com o <code>detail</code> e os agentes dela) e ○ (pendente), e a contagem de agentes por fase. No rodapé: tempo, agentes e ferramentas do workflow.',
        'Tocar num agente abre o transcript dele (tela 16b). Tocar no topo do card recolhe numa linha.'), wf_variants),
])

page += '</body></html>'
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'w').write(page)
print('ok', len(page))
