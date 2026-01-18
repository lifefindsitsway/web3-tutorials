/**
 * MathJax 配置文件
 * 支持分隔符: $$...$$, $...$, \[...\], \(...\)
 * 兼容 Material for MkDocs 的 instant loading
 * 使用 TeX 字体以获得更好的显示效果
 */
window.MathJax = {
  tex: {
    inlineMath: [
      ['$', '$'],
      ['\\(', '\\)']
    ],
    displayMath: [
      ['$$', '$$'],
      ['\\[', '\\]']
    ],
    processEscapes: true,
    processEnvironments: true,
    tags: 'ams'
  },
  chtml: {
    // 使用 MathJax 的 TeX 字体，这是最接近 LaTeX 原生效果的字体
    fontURL: 'https://cdn.jsdelivr.net/npm/mathjax@3/es5/output/chtml/fonts/woff-v2',
    // 缩放比例，可根据正文字体大小调整
    scale: 1,
    // 最小缩放比例
    minScale: 0.5,
    // 匹配周围文本的 ex 高度
    matchFontHeight: true,
    // 数学公式的基线对齐
    mtextInheritFont: false,
    // 使用 TeX 字体渲染普通文本
    merrorInheritFont: true
  },
  options: {
    ignoreHtmlClass: '.*|',
    processHtmlClass: 'arithmatex',
    // 渲染后不添加右键菜单（可选，减少干扰）
    enableMenu: true,
    // 数学公式可被选中复制
    enableEnrichment: true
  },
  startup: {
    ready: function() {
      MathJax.startup.defaultReady();
      MathJax.startup.promise.then(function() {
        console.log('MathJax initial typeset complete');
      });
    }
  }
};

// 兼容 Material for MkDocs 的 instant loading
// 当页面通过 instant loading 切换时，重新渲染公式
if (typeof document$ !== 'undefined') {
  document$.subscribe(function() {
    if (typeof MathJax !== 'undefined' && MathJax.typesetPromise) {
      MathJax.startup.output.clearCache();
      MathJax.typesetClear();
      MathJax.texReset();
      MathJax.typesetPromise();
    }
  });
} else {
  document.addEventListener('DOMContentLoaded', function() {
    if (typeof MathJax !== 'undefined' && MathJax.typesetPromise) {
      MathJax.typesetPromise();
    }
  });
}
