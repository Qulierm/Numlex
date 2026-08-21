// Domain types for notebook engine
// Row kinds produced per line
// kind: 'skip' | 'blank' | 'title' | 'number' | 'variable' | 'error'
// number: { kind:'number', value:number, unit?:string, sourceUnit?:string }
// variable: { kind:'variable', name:string, value:number }
// error: { kind:'error', message?:string }
// blank/title: no value
