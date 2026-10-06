extends SceneTree

# Runs the actual HTML script in isolated DOM/HTTP fixtures. This verifies
# cross-tab account conditions and immutable retry, not browser rendering.
# Requires TK_NODE to point to a Node >=22 runtime; no external packages.
const SCRIPT: String = """const fs=require('node:fs'),vm=require('node:vm'),crypto=require('node:crypto');
const script=fs.readFileSync(process.argv[2],'utf8').split('<script>')[1].split('</script>')[0];
let checks=0,cookieAccount='account-A',mutations=0,failNext=true;const requests=[];
function assert(value,message){checks++;if(!value)throw Error(message);}
function element(){return {hidden:false,disabled:false,value:'',textContent:'',children:[],listeners:{},classList:{toggle(){}},setAttribute(){},addEventListener(name,fn){this.listeners[name]=fn},replaceChildren(...nodes){this.children=nodes},append(...nodes){this.children.push(...nodes)},focus(){},select(){}};}
function member(account='account-A'){return {ok:true,protocol:1,room:{id:'room_'+account,name:'云房间',capacity:2,members:[{id:'member_'+account,name:'城主',seat:1,team:'blue'}]},actor:{id:'member_'+account,name:'城主'},authorityId:'auth_'+account,accessToken:'a'.repeat(64),recoveryKey:'b'.repeat(64),inviteCode:'c'.repeat(64)};}
const json=(status,payload)=>({ok:status>=200&&status<300,status,json:async()=>payload});
async function fetch(path,init={}){const headers=init.headers||{},expected=headers['X-Expected-Account'];requests.push({path,headers:{...headers},body:init.body});
 if(path==='/auth/config')return json(200,{enabled:true});
 if(path==='/auth/login'){assert(expected===undefined,'explicit login does not send stale account condition');const input=JSON.parse(init.body);cookieAccount=input.email.startsWith('B')?'account-B':'account-A';return json(200,{ok:true,sessionToken:'d'.repeat(64),user:{id:cookieAccount,email:input.email}});}
 if(!cookieAccount||expected&&expected!==cookieAccount)return json(401,{error:{code:'ACCOUNT_CHANGED',message:'账号已改变，请重新登录'}});
 if(path==='/auth/logout'){cookieAccount=null;return json(200,{ok:true});}
 if(path==='/auth/me')return json(200,{ok:true,user:{id:cookieAccount,email:cookieAccount+'@example.test'}});
 if(path==='/lobby/mine'){const p=member(cookieAccount);return json(200,{ok:true,rooms:[{room:p.room,seat:1,actor:p.actor,authorityId:p.authorityId}]});}
 if(path.startsWith('/lobby/')){if(failNext){failNext=false;throw Error('controlled pre-commit lost transport');}mutations++;return json(200,member(cookieAccount));}
 if(path==='/api/health')return json(200,{...member(cookieAccount),mode:'shared'});
 return json(404,{});
}
function makeWindow(){const elements=new Map(),$=id=>{if(!elements.has(id))elements.set(id,element());return elements.get(id);};const navigations=[];
 const context=vm.createContext({document:{getElementById:$,querySelectorAll:()=>[],createElement:()=>element()},crypto:crypto.webcrypto,AbortController,URL,fetch,setTimeout,clearTimeout,location:{origin:'https://game.example.test',replace:url=>navigations.push(url)},window:{addEventListener(){}},navigator:{clipboard:{writeText:async()=>{}}}});vm.runInContext(script,context);return{context,$,navigations};}
const run=(page,code)=>vm.runInContext(code,page.context);const settle=async()=>{for(let n=0;n<4;n++)await new Promise(r=>setImmediate(r));};
(async()=>{const A=makeWindow(),A2=makeWindow(),A3=makeWindow(),A4=makeWindow(),A5=makeWindow();await settle();assert(run(A,'user.id')==='account-A','first window verified account A');
 run(A,"start('create',{requestId:'e'.repeat(64),roomName:'A room',capacity:2,playerName:'A'})");await settle();const first=requests.find(r=>r.path==='/lobby/create');assert(run(A,'pending.expectedAccountId')==='account-A'&&run(A,'!busy'),'uncertain enrollment freezes original account in window memory');assert(first.headers['X-Expected-Account']==='account-A','first signup binds account A');assert(mutations===0,'controlled first attempt did not commit');
 const B=makeWindow();await settle();await run(B,'logout()');B.$('email').value='B@example.test';B.$('password').value='synthetic-password';await B.$('login-form').listeners.submit({preventDefault(){}});assert(cookieAccount==='account-B'&&run(B,'user.id')==='account-B','second window explicitly signs in B and changes shared cookie');
 await run(A,'send()');const retry=requests.filter(r=>r.path==='/lobby/create').at(-1);assert(retry.body===first.body&&retry.headers['X-Expected-Account']==='account-A','A retry preserves exact wire body and expected account despite cookie B');assert(mutations===0,'cookie-changed retry creates no room for B');assert(run(A,'user===null&&pending===null&&session===null'),'A does not display or adopt B room after account change');assert(run(B,'user.id')==='account-B'&&cookieAccount==='account-B','B identity and cookie remain intact');
 await run(A2,'logout()');assert(cookieAccount==='account-B','A stale logout cannot revoke or clear B cookie');assert(A2.$('status').textContent.includes('未退出其他账号'),'stale logout explains other account was not signed out');assert(requests.filter(r=>r.path==='/auth/logout').at(-1).headers['X-Expected-Account']==='account-A','logout captures A before clearing form identity');
 await run(A3,'loadRooms()');assert(run(A3,'user===null')&&A3.$('my-rooms').children.length===0,'stale mine adopts no B room list');assert(requests.filter(r=>r.path==='/lobby/mine').at(-1).headers['X-Expected-Account']==='account-A','mine remains bound to verified A');
 await run(A4,"authRequest('/auth/me')");assert(run(A4,'user===null'),'stale me clears A without adopting B');assert(requests.filter(r=>r.path==='/auth/me').at(-1).headers['X-Expected-Account']==='account-A','me carries account A condition');
 A5.context.fixture=member('account-A');run(A5,'showSession(fixture)');await A5.$('enter-game').listeners.click();assert(A5.navigations.length===0&&run(A5,'user===null&&session===null'),'stale health cannot navigate into B or retain old account result');assert(requests.filter(r=>r.path==='/api/health').at(-1).headers['X-Expected-Account']==='account-A','room health binds expected account as well as room bearer');
 console.log(JSON.stringify({checks,failures:0,scope:'actual cloud-lobby script; isolated DOM/HTTP fixture; five shared-cookie windows',mutationsAfterAccountChange:mutations}));
})().catch(error=>{console.error(error.stack);process.exitCode=1});
"""

func _initialize() -> void:
	var node: String = OS.get_environment("TK_NODE")
	if node.is_empty():
		push_error("Cloud HTML account test requires TK_NODE; no test was run")
		quit(1)
		return
	var output: Array = []
	var encoded: String = Marshalls.raw_to_base64(SCRIPT.to_utf8_buffer())
	var result: int = OS.execute(node, ["-e", "eval(Buffer.from(process.argv[1],'base64').toString('utf8'))", encoded, ProjectSettings.globalize_path("res://bridge/cloud-lobby.html")], output, true)
	for item: Variant in output:
		print(str(item).strip_edges())
	var payload: Variant = JSON.parse_string("".join(output).strip_edges()) if result == 0 else null
	if not payload is Dictionary or payload.get("failures") != 0 or payload.get("checks") != 19 or payload.get("mutationsAfterAccountChange") != 0:
		push_error("Cloud HTML account consistency test did not pass")
		quit(1)
		return
	print("Cloud HTML script account checks: 19 passed, 0 failed")
	quit(0)
