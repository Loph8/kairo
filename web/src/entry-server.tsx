import { renderToString } from 'react-dom/server'
import App from './App'

/** Server-side render of the whole page body. The client replaces it once the JavaScript loads. */
export function render(): string {
  return renderToString(<App />)
}
