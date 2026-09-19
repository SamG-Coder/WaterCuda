// Experimental post-emission pass. Never imported by the production compiler.
// Intentionally recognizes only constructors made from uniform fields and
// typed literals. Unknown expressions, calls, indexing and mutable reads stay.
export function tokens(source){
 const out=[];let i=0;
 while(i<source.length){
  if(/\s/.test(source[i])){i++;continue;}
  if(source.startsWith('//',i)){const end=source.indexOf('\n',i);i=end<0?source.length:end;continue;}
  if(source.startsWith('/*',i)){let depth=1;i+=2;while(depth&&i<source.length){if(source.startsWith('/*',i)){depth++;i+=2;}else if(source.startsWith('*/',i)){depth--;i+=2;}else i++;}if(depth)throw Error('Unterminated WGSL comment');continue;}
  const match=/^(?:[A-Za-z_]\w*|0[xX][\da-fA-F]+(?:\.[\da-fA-F]*)?(?:[pP][+-]?\d+)?[iufh]?|(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?[iufh]?|!=|==|<=|>=|&&|\|\||[^\s])/.exec(source.slice(i));
  out.push({value:match[0],start:i,end:i+match[0].length});i+=match[0].length;
 }
 return out;
}
export function pairs(t){const result=new Map(),stack=[];for(let i=0;i<t.length;i++){const v=t[i].value;if(v==='('||v==='{')stack.push(i);else if(v===')'||v==='}'){const open=stack.pop();if(open===undefined||t[open].value!==(v===')'?'(':'{'))throw Error('Unbalanced WGSL');result.set(open,i);}}if(stack.length)throw Error('Unbalanced WGSL');return result;}
function structs(t,match){
 const result=new Map();
 for(let i=0;i<t.length-2;i++)if(t[i].value==='struct'&&t[i+2].value==='{'){
  const fields=[];const end=match.get(i+2);
  for(let j=i+3;j<end;j++)if(t[j+1]?.value===':'){
   let k=j+2,angle=0;for(;k<end;k++){const v=t[k].value;if(v==='<')angle++;if(v==='>')angle--;if(v===','&&!angle)break;}
   fields.push({name:t[j].value,type:t.slice(j+2,k).map(x=>x.value).join('')});j=k;
  }
  result.set(t[i+1].value,fields);i=end;
 }
 return result;
}
export function apply(source,edits){let output='',cursor=0;for(const e of edits){output+=source.slice(cursor,e.start)+e.text;cursor=e.end;}return output+source.slice(cursor);}

export function trimWgsl(artifact){
 let source=artifact.wgsl,projections=0,removedFunctions=0;
 // Multiple sweeps allow nested struct selections to collapse independently.
 for(let sweep=0;sweep<16;sweep++){
  const t=tokens(source),match=pairs(t),types=structs(t,match),uniforms=new Map();
  for(let i=0;i<t.length-6;i++)if(t[i].value==='var'&&t[i+1].value==='<'&&t[i+2].value==='uniform'&&t[i+3].value==='>'&&t[i+5].value===':')uniforms.set(t[i+4].value,new Map((types.get(t[i+6].value)||[]).map(f=>[f.name,f.type])));
  const pure=(from,to)=>{
   let i=from;
   const expression=()=>{
    let type;
    const v=t[i]?.value;
    if(v==='('){i++;type=expression();if(t[i++]?.value!==')')return null;}
    else if(uniforms.has(v)&&t[i+1]?.value==='.') {type=uniforms.get(v).get(t[i+2]?.value);i+=3;}
    else if(v==='true'||v==='false'){type='bool';i++;}
    else if(/^(?:\d|\.)/.test(v??'')){type=v.endsWith('u')?'u32':v.endsWith('i')?'i32':v.endsWith('f')?'f32':v.endsWith('h')?'f16':null;i++;}
    else if(types.has(v)||/^vec[234]$/.test(v??'')||['u32','i32','f32','f16','bool'].includes(v)){
     type=v;i++;
     if(t[i]?.value==='<'){type+='<';i++;while(i<to&&t[i].value!=='>')type+=t[i++].value;if(t[i++]?.value!=='>')return null;type+='>';}
     if(t[i++]?.value!=='(')return null;
     if(t[i]?.value!==')')while(i<to){if(!expression())return null;if(t[i]?.value!==',')break;i++;}
     if(t[i++]?.value!==')')return null;
    }else return null;
    if(!type)return null;
    if(['!=','=='].includes(t[i]?.value)){i++;if(!expression())return null;type='bool';}
    return type;
   };
   const type=expression();return i===to?type:null;
  };
  // A same-named local/parameter could hide a uniform; conservatively disable
  // that uniform rather than attempting scope resolution in this small pass.
  for(const name of uniforms.keys())if(t.filter((x,i)=>x.value===name&&[':', '='].includes(t[i+1]?.value)).length>1)uniforms.delete(name);
  const edits=[];
  for(let i=0;i<t.length-4;i++){
   const fields=types.get(t[i].value);if(!fields||t[i+1].value!=='(')continue;
   const close=match.get(i+1);if(t[close+1]?.value!=='.')continue;
   const field=fields.findIndex(f=>f.name===t[close+2]?.value);if(field<0)continue;
   const args=[];let start=i+2;
   for(let j=start;j<close;j++){if(t[j].value==='('){j=match.get(j);continue;}if(t[j].value===','){args.push([start,j]);start=j+1;}}
   args.push([start,close]);if(args.length!==fields.length)continue;
   const inferred=args.map(([a,b])=>pure(a,b));
   if(inferred.some(x=>!x)||inferred[field]!==fields[field].type)continue;
   const [a,b]=args[field];edits.push({start:t[i].start,end:t[close+2].end,text:'('+source.slice(t[a].start,t[b-1].end)+')'});projections++;i=close+2;
  }
  if(!edits.length)break;source=apply(source,edits);
 }
 // Call-graph reachability. Keep all entry points and all module-level
 // references; only strip unreachable functions, never bindings or ABI fields.
 const t=tokens(source),match=pairs(t),functions=new Map();let declarationStart=0;
 for(let i=0;i<t.length;i++){
  if(t[i].value==='fn'){
   let body=i+2;while(body<t.length&&t[body].value!=='{')body++;
   const end=match.get(body),prefix=t.slice(declarationStart,i).map(x=>x.value);
   functions.set(t[i+1].value,{start:t[declarationStart].start,end:t[end].end,body:t.slice(body+1,end),entry:prefix.some(v=>['compute','vertex','fragment'].includes(v))});i=end;declarationStart=i+1;
  }else if(t[i].value==='{'){i=match.get(i);declarationStart=i+1;}
  else if(t[i].value===';')declarationStart=i+1;
 }
 const live=new Set([artifact.entryPoint||'main',...[...functions].filter(([,f])=>f.entry).map(([name])=>name)]);
 const outside=apply(source,[...functions.values()].map(f=>({...f,text:''})));for(const x of tokens(outside))if(functions.has(x.value))live.add(x.value);
 const todo=[...live];while(todo.length){const f=functions.get(todo.pop());if(!f)continue;for(const x of f.body)if(functions.has(x.value)&&!live.has(x.value)){live.add(x.value);todo.push(x.value);}}
 const dead=[...functions].filter(([name])=>!live.has(name)).map(([,f])=>({...f,text:''}));removedFunctions=dead.length;source=apply(source,dead);
 return {artifact:{...artifact,wgsl:source},stats:{beforeBytes:artifact.wgsl.length,afterBytes:source.length,projections,removedFunctions}};
}
