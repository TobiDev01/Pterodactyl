import React from 'react';
import ReactDOM from 'react-dom';
import App from '@/components/App';
import { setConfig } from 'react-hot-loader';
import './theme-2.css';

import './i18n';
setConfig({ reloadHooks: false });

ReactDOM.render(<App />, document.getElementById('app'));