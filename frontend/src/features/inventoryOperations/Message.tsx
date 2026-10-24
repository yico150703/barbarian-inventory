export function Message({error}:{error:string}){return error?<p className="io-error" role="alert">{error}</p>:null}
