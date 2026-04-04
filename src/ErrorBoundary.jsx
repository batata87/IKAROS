import React from 'react';

export class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { err: null };
  }

  static getDerivedStateFromError(err) {
    return { err };
  }

  render() {
    if (this.state.err) {
      return (
        <div
          style={{
            position: 'fixed',
            inset: 0,
            padding: 24,
            background: '#1e293b',
            color: '#fecaca',
            fontFamily: 'ui-monospace, monospace',
            fontSize: 13,
            overflow: 'auto',
            zIndex: 99999,
          }}
        >
          <strong>IKAROS crashed</strong>
          <pre style={{ marginTop: 12, whiteSpace: 'pre-wrap' }}>{String(this.state.err)}</pre>
        </div>
      );
    }
    return this.props.children;
  }
}
