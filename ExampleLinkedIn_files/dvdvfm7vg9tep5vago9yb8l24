!function(t){"object"==typeof module&&module.exports?(t.default=t,module.exports=t):"function"==typeof define&&define.amd?define("highcharts/modules/map",["highcharts"],(function(e){t(e)
t.Highcharts=e
return t})):t("undefined"!=typeof Highcharts?Highcharts:void 0)}((function(t){function e(t,e,i,o){t.hasOwnProperty(e)||(t[e]=o.apply(null,i))}e(t=t?t._modules:{},"Core/Axis/MapAxis.js",[t["Core/Axis/Axis.js"],t["Core/Utilities.js"]],(function(t,e){var i=e.addEvent,o=e.pick,r=function(t){this.axis=t}
e=function(){function t(){}t.compose=function(t){t.keepProps.push("mapAxis")
i(t,"init",(function(){this.mapAxis||(this.mapAxis=new r(this))}))
i(t,"getSeriesExtremes",(function(){if(this.mapAxis){var t=[]
this.isXAxis&&(this.series.forEach((function(e,i){e.useMapGeometry&&(t[i]=e.xData,e.xData=[])})),this.mapAxis.seriesXData=t)}}))
i(t,"afterGetSeriesExtremes",(function(){if(this.mapAxis){var t,e=this.mapAxis.seriesXData||[]
if(this.isXAxis){var i=o(this.dataMin,Number.MAX_VALUE),r=o(this.dataMax,-Number.MAX_VALUE)
this.series.forEach((function(s,n){s.useMapGeometry&&(i=Math.min(i,o(s.minX,i)),r=Math.max(r,o(s.maxX,r)),s.xData=e[n],t=!0)}))
t&&(this.dataMin=i,this.dataMax=r)
this.mapAxis.seriesXData=void 0}}}))
i(t,"afterSetAxisTranslation",(function(){if(this.mapAxis){var t,e=this.chart,i=e.plotWidth/e.plotHeight
e=e.xAxis[0]
"yAxis"===this.coll&&void 0!==e.transA&&this.series.forEach((function(e){e.preserveAspectRatio&&(t=!0)}))
if(t&&(this.transA=e.transA=Math.min(this.transA,e.transA),e=((i=1>(i/=(e.max-e.min)/(this.max-this.min))?this:e).max-i.min)*i.transA,i.mapAxis.pixelPadding=i.len-e,i.minPixelPadding=i.mapAxis.pixelPadding/2,e=i.mapAxis.fixTo)){e=e[1]-i.toValue(e[0],!0)
e*=i.transA;(Math.abs(e)>i.minPixelPadding||i.min===i.dataMin&&i.max===i.dataMax)&&(e=0)
i.minPixelPadding-=e}}}))
i(t,"render",(function(){this.mapAxis&&(this.mapAxis.fixTo=void 0)}))}
return t}()
e.compose(t)
return e}))
e(t,"Mixins/ColorSeries.js",[],(function(){return{colorPointMixin:{setVisible:function(t){var e=this,i=t?"show":"hide"
e.visible=e.options.visible=!!t;["graphic","dataLabel"].forEach((function(t){e[t]&&e[t][i]()}))
this.series.buildKDTree()}},colorSeriesMixin:{optionalAxis:"colorAxis",colorAxis:0,translateColors:function(){var t=this,e=this.options.nullColor,i=this.colorAxis,o=this.colorKey;(this.data.length?this.data:this.points).forEach((function(r){var s=r.getNestedProperty(o);(s=r.options.color||(r.isNull||null===r.value?e:i&&void 0!==s?i.toColor(s,r):r.color||t.color))&&r.color!==s&&(r.color=s,"point"===t.options.legendType&&r.legendItem&&t.chart.legend.colorizeItem(r,r.visible))}))}}}}))
e(t,"Core/Axis/ColorAxis.js",[t["Core/Axis/Axis.js"],t["Core/Chart/Chart.js"],t["Core/Color/Color.js"],t["Mixins/ColorSeries.js"],t["Core/Animation/Fx.js"],t["Core/Globals.js"],t["Core/Legend.js"],t["Mixins/LegendSymbol.js"],t["Core/Color/Palette.js"],t["Core/Series/Point.js"],t["Core/Series/Series.js"],t["Core/Utilities.js"]],(function(t,e,i,o,r,s,n,a,l,p,h,c){var u=this&&this.__extends||function(){var t=function(e,i){t=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)e.hasOwnProperty(i)&&(t[i]=e[i])}
return t(e,i)}
return function(e,i){function o(){this.constructor=e}t(e,i)
e.prototype=null===i?Object.create(i):(o.prototype=i.prototype,new o)}}(),d=i.parse
i=o.colorPointMixin
o=o.colorSeriesMixin
var f=s.noop,m=c.addEvent,y=c.erase,g=c.extend,b=c.isNumber,x=c.merge,v=c.pick,M=c.splat
g(h.prototype,o)
g(p.prototype,i)
e.prototype.collectionsWithUpdate.push("colorAxis")
e.prototype.collectionsWithInit.colorAxis=[e.prototype.addColorAxis]
var C=function(t){function e(e,i){var o=t.call(this,e,i)||this
o.beforePadding=!1
o.chart=void 0
o.coll="colorAxis"
o.dataClasses=void 0
o.legendItem=void 0
o.legendItems=void 0
o.name=""
o.options=void 0
o.stops=void 0
o.visible=!0
o.init(e,i)
return o}u(e,t)
e.prototype.init=function(i,o){var r=i.options.legend||{},s=o.layout?"vertical"!==o.layout:"vertical"!==r.layout
r=x(e.defaultOptions,o,{showEmpty:!1,title:null,visible:r.enabled&&(!o||!1!==o.visible)})
this.coll="colorAxis"
this.side=o.side||s?2:1
this.reversed=o.reversed||!s
this.opposite=!s
i.options[this.coll]=r
t.prototype.init.call(this,i,r)
o.dataClasses&&this.initDataClasses(o)
this.initStops()
this.horiz=s
this.zoomEnabled=!1}
e.prototype.initDataClasses=function(t){var e,i=this.chart,o=0,r=i.options.chart.colorCount,s=this.options,n=t.dataClasses.length
this.dataClasses=e=[]
this.legendItems=[]
t.dataClasses.forEach((function(t,a){t=x(t)
e.push(t)
!i.styledMode&&t.color||("category"===s.dataClassColor?(i.styledMode||(a=i.options.colors,r=a.length,t.color=a[o]),t.colorIndex=o,++o===r&&(o=0)):t.color=d(s.minColor).tweenTo(d(s.maxColor),2>n?.5:a/(n-1)))}))}
e.prototype.hasData=function(){return!!(this.tickPositions||[]).length}
e.prototype.setTickPositions=function(){if(!this.dataClasses)return t.prototype.setTickPositions.call(this)}
e.prototype.initStops=function(){this.stops=this.options.stops||[[0,this.options.minColor],[1,this.options.maxColor]]
this.stops.forEach((function(t){t.color=d(t[1])}))}
e.prototype.setOptions=function(e){t.prototype.setOptions.call(this,e)
this.options.crosshair=this.options.marker}
e.prototype.setAxisSize=function(){var t,i,o=this.legendSymbol,r=this.chart,s=r.options.legend||{}
o?(this.left=s=o.attr("x"),this.top=t=o.attr("y"),this.width=i=o.attr("width"),this.height=o=o.attr("height"),this.right=r.chartWidth-s-i,this.bottom=r.chartHeight-t-o,this.len=this.horiz?i:o,this.pos=this.horiz?s:t):this.len=(this.horiz?s.symbolWidth:s.symbolHeight)||e.defaultLegendLength}
e.prototype.normalizedValue=function(t){this.logarithmic&&(t=this.logarithmic.log2lin(t))
return 1-(this.max-t)/(this.max-this.min||1)}
e.prototype.toColor=function(t,e){var i,o=this.dataClasses,r=this.stops
if(o)for(i=o.length;i--;){var s=o[i],n=s.from
r=s.to
if((void 0===n||t>=n)&&(void 0===r||t<=r)){var a=s.color
e&&(e.dataClass=i,e.colorIndex=s.colorIndex)
break}}else{t=this.normalizedValue(t)
for(i=r.length;i--&&!(t>r[i][0]););n=r[i]||r[i+1]
t=1-((r=r[i+1]||n)[0]-t)/(r[0]-n[0]||1)
a=n.color.tweenTo(r.color,t)}return a}
e.prototype.getOffset=function(){var e=this.legendGroup,i=this.chart.axisOffset[this.side]
e&&(this.axisParent=e,t.prototype.getOffset.call(this),this.added||(this.added=!0,this.labelLeft=0,this.labelRight=this.width),this.chart.axisOffset[this.side]=i)}
e.prototype.setLegendColor=function(){var t=this.reversed,e=t?1:0
t=t?0:1
e=this.horiz?[e,0,t,0]:[0,t,0,e]
this.legendColor={linearGradient:{x1:e[0],y1:e[1],x2:e[2],y2:e[3]},stops:this.stops}}
e.prototype.drawLegendSymbol=function(t,i){var o=t.padding,r=t.options,s=this.horiz,n=v(r.symbolWidth,s?e.defaultLegendLength:12),a=v(r.symbolHeight,s?12:e.defaultLegendLength),l=v(r.labelPadding,s?16:30)
r=v(r.itemDistance,10)
this.setLegendColor()
i.legendSymbol=this.chart.renderer.rect(0,t.baseline-11,n,a).attr({zIndex:1}).add(i.legendGroup)
this.legendItemWidth=n+o+(s?r:l)
this.legendItemHeight=a+o+(s?l:0)}
e.prototype.setState=function(t){this.series.forEach((function(e){e.setState(t)}))}
e.prototype.setVisible=function(){}
e.prototype.getSeriesExtremes=function(){var t,e=this.series,i=e.length
this.dataMin=1/0
for(this.dataMax=-1/0;i--;){var o=e[i],r=o.colorKey=v(o.options.colorKey,o.colorKey,o.pointValKey,o.zoneAxis,"y"),s=o.pointArrayMap,n=o[r+"Min"]&&o[r+"Max"]
if(o[r+"Data"])var a=o[r+"Data"]
else if(s){a=[]
s=s.indexOf(r)
var l=o.yData
if(0<=s&&l)for(t=0;t<l.length;t++)a.push(v(l[t][s],l[t]))}else a=o.yData
n?(o.minColorValue=o[r+"Min"],o.maxColorValue=o[r+"Max"]):(a=h.prototype.getExtremes.call(o,a),o.minColorValue=a.dataMin,o.maxColorValue=a.dataMax)
void 0!==o.minColorValue&&(this.dataMin=Math.min(this.dataMin,o.minColorValue),this.dataMax=Math.max(this.dataMax,o.maxColorValue))
n||h.prototype.applyExtremes.call(o)}}
e.prototype.drawCrosshair=function(e,i){var o=i&&i.plotX,r=i&&i.plotY,s=this.pos,n=this.len
if(i){var a=this.toPixels(i.getNestedProperty(i.series.colorKey))
a<s?a=s-2:a>s+n&&(a=s+n+2)
i.plotX=a
i.plotY=this.len-a
t.prototype.drawCrosshair.call(this,e,i)
i.plotX=o
i.plotY=r
this.cross&&!this.cross.addedToColorAxis&&this.legendGroup&&(this.cross.addClass("highcharts-coloraxis-marker").add(this.legendGroup),this.cross.addedToColorAxis=!0,!this.chart.styledMode&&this.crosshair&&this.cross.attr({fill:this.crosshair.color}))}}
e.prototype.getPlotLinePath=function(e){var i=this.left,o=e.translatedValue,r=this.top
return b(o)?this.horiz?[["M",o-4,r-6],["L",o+4,r-6],["L",o,r],["Z"]]:[["M",i,o],["L",i-6,o+6],["L",i-6,o-6],["Z"]]:t.prototype.getPlotLinePath.call(this,e)}
e.prototype.update=function(e,i){var o=this.chart.legend
this.series.forEach((function(t){t.isDirtyData=!0}));(e.dataClasses&&o.allItems||this.dataClasses)&&this.destroyItems()
t.prototype.update.call(this,e,i)
this.legendItem&&(this.setLegendColor(),o.colorizeItem(this,!0))}
e.prototype.destroyItems=function(){var t=this.chart
this.legendItem?t.legend.destroyItem(this):this.legendItems&&this.legendItems.forEach((function(e){t.legend.destroyItem(e)}))
t.isDirtyLegend=!0}
e.prototype.destroy=function(){this.chart.isDirtyLegend=!0
this.destroyItems()
t.prototype.destroy.apply(this,[].slice.call(arguments))}
e.prototype.remove=function(e){this.destroyItems()
t.prototype.remove.call(this,e)}
e.prototype.getDataClassLegendSymbols=function(){var t,e=this,i=e.chart,o=e.legendItems,r=i.options.legend,s=r.valueDecimals,n=r.valueSuffix||""
o.length||e.dataClasses.forEach((function(r,l){var p=!0,h=r.from,c=r.to,u=i.numberFormatter
t=""
void 0===h?t="< ":void 0===c&&(t="> ")
void 0!==h&&(t+=u(h,s)+n)
void 0!==h&&void 0!==c&&(t+=" - ")
void 0!==c&&(t+=u(c,s)+n)
o.push(g({chart:i,name:t,options:{},drawLegendSymbol:a.drawRectangle,visible:!0,setState:f,isDataClass:!0,setVisible:function(){p=e.visible=!p
e.series.forEach((function(t){t.points.forEach((function(t){t.dataClass===l&&t.setVisible(p)}))}))
i.legend.colorizeItem(this,p)}},r))}))
return o}
e.defaultLegendLength=200
e.defaultOptions={lineWidth:0,minPadding:0,maxPadding:0,gridLineWidth:1,tickPixelInterval:72,startOnTick:!0,endOnTick:!0,offset:0,marker:{animation:{duration:50},width:.01,color:l.neutralColor40},labels:{overflow:"justify",rotation:0},minColor:l.highlightColor10,maxColor:l.highlightColor100,tickLength:5,showInLegend:!0}
e.keepProps=["legendGroup","legendItemHeight","legendItemWidth","legendItem","legendSymbol"]
return e}(t)
Array.prototype.push.apply(t.keepProps,C.keepProps)
s.ColorAxis=C;["fill","stroke"].forEach((function(t){r.prototype[t+"Setter"]=function(){this.elem.attr(t,d(this.start).tweenTo(d(this.end),this.pos),null,!0)}}))
m(e,"afterGetAxes",(function(){var t=this,e=t.options
this.colorAxis=[]
e.colorAxis&&(e.colorAxis=M(e.colorAxis),e.colorAxis.forEach((function(e,i){e.index=i
new C(t,e)})))}))
m(h,"bindAxes",(function(){var t=this.axisTypes
t?-1===t.indexOf("colorAxis")&&t.push("colorAxis"):this.axisTypes=["colorAxis"]}))
m(n,"afterGetAllItems",(function(t){var e,i,o=[];(this.chart.colorAxis||[]).forEach((function(i){(e=i.options)&&e.showInLegend&&(e.dataClasses&&e.visible?o=o.concat(i.getDataClassLegendSymbols()):e.visible&&o.push(i),i.series.forEach((function(i){i.options.showInLegend&&!e.dataClasses||("point"===i.options.legendType?i.points.forEach((function(e){y(t.allItems,e)})):y(t.allItems,i))})))}))
for(i=o.length;i--;)t.allItems.unshift(o[i])}))
m(n,"afterColorizeItem",(function(t){t.visible&&t.item.legendColor&&t.item.legendSymbol.attr({fill:t.item.legendColor})}))
m(n,"afterUpdate",(function(){var t=this.chart.colorAxis
t&&t.forEach((function(t,e,i){t.update({},i)}))}))
m(h,"afterTranslate",(function(){(this.chart.colorAxis&&this.chart.colorAxis.length||this.colorAttribs)&&this.translateColors()}))
return C}))
e(t,"Mixins/ColorMapSeries.js",[t["Core/Globals.js"],t["Core/Series/Point.js"],t["Core/Utilities.js"]],(function(t,e,i){var o=i.defined
return{colorMapPointMixin:{dataLabelOnNull:!0,isValid:function(){return null!==this.value&&1/0!==this.value&&-1/0!==this.value},setState:function(t){e.prototype.setState.call(this,t)
this.graphic&&this.graphic.attr({zIndex:"hover"===t?1:0})}},colorMapSeriesMixin:{pointArrayMap:["value"],axisTypes:["xAxis","yAxis","colorAxis"],trackerGroups:["group","markerGroup","dataLabelsGroup"],getSymbol:t.noop,parallelArrays:["x","y","value"],colorKey:"value",pointAttribs:t.seriesTypes.column.prototype.pointAttribs,colorAttribs:function(t){var e={}
o(t.color)&&(e[this.colorProp||"fill"]=t.color)
return e}}}}))
e(t,"Maps/MapNavigationOptionsDefault.js",[t["Core/Options.js"],t["Core/Utilities.js"]],(function(t,e){(e=e.extend)(t.defaultOptions.lang,{zoomIn:"Zoom in",zoomOut:"Zoom out"})
return t.defaultOptions.mapNavigation={buttonOptions:{alignTo:"plotBox",align:"left",verticalAlign:"top",x:0,width:18,height:18,padding:5,style:{fontSize:"15px",fontWeight:"bold"},theme:{"stroke-width":1,"text-align":"center"}},buttons:{zoomIn:{onclick:function(){this.mapZoom(.5)},text:"+",y:0},zoomOut:{onclick:function(){this.mapZoom(2)},text:"-",y:28}},mouseWheelSensitivity:1.1}}))
e(t,"Maps/MapNavigation.js",[t["Core/Chart/Chart.js"],t["Core/Globals.js"],t["Core/Utilities.js"]],(function(t,e,i){function o(t){t&&(t.preventDefault&&t.preventDefault(),t.stopPropagation&&t.stopPropagation(),t.cancelBubble=!0)}function r(t){this.init(t)}var s=e.doc,n=i.addEvent,a=i.extend,l=i.merge,p=i.objectEach,h=i.pick
r.prototype.init=function(t){this.chart=t
t.mapNavButtons=[]}
r.prototype.update=function(t){var e,i,r,s,c,u=this.chart,d=u.options.mapNavigation,f=function(t){this.handler.call(u,t)
o(t)},m=u.mapNavButtons
t&&(d=u.options.mapNavigation=l(u.options.mapNavigation,t))
for(;m.length;)m.pop().destroy()
h(d.enableButtons,d.enabled)&&!u.renderer.forExport&&p(d.buttons,(function(t,p){e=l(d.buttonOptions,t)
u.styledMode||((i=e.theme).style=l(e.theme.style,e.style),s=(r=i.states)&&r.hover,c=r&&r.select);(t=u.renderer.button(e.text,0,0,f,i,s,c,0,"zoomIn"===p?"topbutton":"bottombutton").addClass("highcharts-map-navigation highcharts-"+{zoomIn:"zoom-in",zoomOut:"zoom-out"}[p]).attr({width:e.width,height:e.height,title:u.options.lang[p],padding:e.padding,zIndex:5}).add()).handler=e.onclick
n(t.element,"dblclick",o)
m.push(t)
var h=e,y=n(u,"load",(function(){t.align(a(h,{width:t.width,height:2*t.height}),null,h.alignTo)
y()}))}))
this.updateEvents(d)}
r.prototype.updateEvents=function(t){var e=this.chart
h(t.enableDoubleClickZoom,t.enabled)||t.enableDoubleClickZoomTo?this.unbindDblClick=this.unbindDblClick||n(e.container,"dblclick",(function(t){e.pointer.onContainerDblClick(t)})):this.unbindDblClick&&(this.unbindDblClick=this.unbindDblClick())
h(t.enableMouseWheelZoom,t.enabled)?this.unbindMouseWheel=this.unbindMouseWheel||n(e.container,void 0===s.onmousewheel?"DOMMouseScroll":"mousewheel",(function(t){e.pointer.onContainerMouseWheel(t)
o(t)
return!1})):this.unbindMouseWheel&&(this.unbindMouseWheel=this.unbindMouseWheel())}
a(t.prototype,{fitToBox:function(t,e){[["x","width"],["y","height"]].forEach((function(i){var o=i[0]
i=i[1]
t[o]+t[i]>e[o]+e[i]&&(t[i]>e[i]?(t[i]=e[i],t[o]=e[o]):t[o]=e[o]+e[i]-t[i])
t[i]>e[i]&&(t[i]=e[i])
t[o]<e[o]&&(t[o]=e[o])}))
return t},mapZoom:function(t,e,i,o,r){var s=this.xAxis[0],n=s.max-s.min,a=h(e,s.min+n/2),l=n*t,p=(n=this.yAxis[0]).max-n.min,c=h(i,n.min+p/2)
p*=t
l=(a=this.fitToBox({x:a-l*(o?(o-s.pos)/s.len:.5),y:c-p*(r?(r-n.pos)/n.len:.5),width:l,height:p},{x:s.dataMin,y:n.dataMin,width:s.dataMax-s.dataMin,height:n.dataMax-n.dataMin})).x<=s.dataMin&&a.width>=s.dataMax-s.dataMin&&a.y<=n.dataMin&&a.height>=n.dataMax-n.dataMin
o&&s.mapAxis&&(s.mapAxis.fixTo=[o-s.pos,e])
r&&n.mapAxis&&(n.mapAxis.fixTo=[r-n.pos,i])
void 0===t||l?(s.setExtremes(void 0,void 0,!1),n.setExtremes(void 0,void 0,!1)):(s.setExtremes(a.x,a.x+a.width,!1),n.setExtremes(a.y,a.y+a.height,!1))
this.redraw()}})
n(t,"beforeRender",(function(){this.mapNavigation=new r(this)
this.mapNavigation.update()}))
e.MapNavigation=r}))
e(t,"Maps/MapPointer.js",[t["Core/Pointer.js"],t["Core/Utilities.js"]],(function(t,e){var i=e.extend,o=e.pick
e=e.wrap
i(t.prototype,{onContainerDblClick:function(t){var e=this.chart
t=this.normalize(t)
e.options.mapNavigation.enableDoubleClickZoomTo?e.pointer.inClass(t.target,"highcharts-tracker")&&e.hoverPoint&&e.hoverPoint.zoomTo():e.isInsidePlot(t.chartX-e.plotLeft,t.chartY-e.plotTop)&&e.mapZoom(.5,e.xAxis[0].toValue(t.chartX),e.yAxis[0].toValue(t.chartY),t.chartX,t.chartY)},onContainerMouseWheel:function(t){var e=this.chart,i=(t=this.normalize(t)).detail||-t.wheelDelta/120
e.isInsidePlot(t.chartX-e.plotLeft,t.chartY-e.plotTop)&&e.mapZoom(Math.pow(e.options.mapNavigation.mouseWheelSensitivity,i),e.xAxis[0].toValue(t.chartX),e.yAxis[0].toValue(t.chartY),t.chartX,t.chartY)}})
e(t.prototype,"zoomOption",(function(t){var e=this.chart.options.mapNavigation
o(e.enableTouchZoom,e.enabled)&&(this.chart.options.chart.pinchType="xy")
t.apply(this,[].slice.call(arguments,1))}))
e(t.prototype,"pinchTranslate",(function(t,e,i,o,r,s,n){t.call(this,e,i,o,r,s,n)
"map"===this.chart.options.chart.type&&this.hasZoom&&(t=o.scaleX>o.scaleY,this.pinchTranslateDirection(!t,e,i,o,r,s,n,t?o.scaleX:o.scaleY))}))}))
e(t,"Maps/MapSymbols.js",[t["Core/Globals.js"],t["Core/Renderer/SVG/SVGRenderer.js"]],(function(t,e){function i(t,e,i,o,r,s,n,a){return[["M",t+r,e],["L",t+i-s,e],["C",t+i-s/2,e,t+i,e+s/2,t+i,e+s],["L",t+i,e+o-n],["C",t+i,e+o-n/2,t+i-n/2,e+o,t+i-n,e+o],["L",t+a,e+o],["C",t+a/2,e+o,t,e+o-a/2,t,e+o-a],["L",t,e+r],["C",t,e+r/2,t+r/2,e,t+r,e],["Z"]]}var o=t.Renderer
e.prototype.symbols.topbutton=function(t,e,o,r,s){return i(t-1,e-1,o,r,s=s&&s.r||0,s,0,0)}
e.prototype.symbols.bottombutton=function(t,e,o,r,s){return i(t-1,e-1,o,r,0,0,s=s&&s.r||0,s)}
o!==e&&["topbutton","bottombutton"].forEach((function(t){o.prototype.symbols[t]=e.prototype.symbols[t]}))
return e.prototype.symbols}))
e(t,"Maps/Map.js",[t["Core/Chart/Chart.js"],t["Core/Globals.js"],t["Core/Renderer/SVG/SVGRenderer.js"],t["Core/Utilities.js"]],(function(t,e,i,o){var r,s=o.getOptions,n=o.merge,a=o.pick
!function(e){e.maps={}
e.mapChart=function(e,i,o){var r="string"==typeof e||e.nodeName,l=arguments[r?1:0],p=l,h={endOnTick:!1,visible:!1,minPadding:0,maxPadding:0,startOnTick:!1},c=s().credits,u=l.series
l.series=null;(l=n({chart:{panning:{enabled:!0,type:"xy"},type:"map"},credits:{mapText:a(c.mapText,' © <a href="{geojson.copyrightUrl}">{geojson.copyrightShort}</a>'),mapTextFull:a(c.mapTextFull,"{geojson.copyright}")},tooltip:{followTouchMove:!1},xAxis:h,yAxis:n(h,{reversed:!0})},l,{chart:{inverted:!1,alignTicks:!1}})).series=p.series=u
return r?new t(e,l,o):new t(l,i)}
e.splitPath=function(t){"string"==typeof t&&(t=(t=t.replace(/([A-Za-z])/g," $1 ").replace(/^\s*/,"").replace(/\s*$/,"")).split(/[ ,;]+/).map((function(t){return/[A-za-z]/.test(t)?t:parseFloat(t)})))
return i.prototype.pathToSegments(t)}}(r||(r={}))
e.Map=r.mapChart
e.mapChart=r.mapChart
e.maps=r.maps
return r}))
e(t,"Series/Map/MapPoint.js",[t["Mixins/ColorMapSeries.js"],t["Core/Series/SeriesRegistry.js"],t["Core/Utilities.js"]],(function(t,e,i){var o=this&&this.__extends||function(){var t=function(e,i){return(t=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)e.hasOwnProperty(i)&&(t[i]=e[i])})(e,i)}
return function(e,i){function o(){this.constructor=e}t(e,i)
e.prototype=null===i?Object.create(i):(o.prototype=i.prototype,new o)}}()
t=t.colorMapPointMixin
var r=i.extend
e=function(t){function e(){var e=null!==t&&t.apply(this,arguments)||this
e.options=void 0
e.path=void 0
e.series=void 0
return e}o(e,t)
e.prototype.applyOptions=function(e,i){var o=this.series
e=t.prototype.applyOptions.call(this,e,i)
i=o.joinBy
o.mapData&&o.mapMap&&((i=void 0!==(i=t.prototype.getNestedProperty.call(e,i[1]))&&o.mapMap[i])?(o.xyFromShape&&(e.x=i._midX,e.y=i._midY),r(e,i)):e.value=e.value||null)
return e}
e.prototype.onMouseOver=function(e){i.clearTimeout(this.colorInterval)
null!==this.value||this.series.options.nullInteraction?t.prototype.onMouseOver.call(this,e):this.series.onMouseOut(e)}
e.prototype.zoomTo=function(){var t=this.series
t.xAxis.setExtremes(this._minX,this._maxX,!1)
t.yAxis.setExtremes(this._minY,this._maxY,!1)
t.chart.redraw()}
return e}(e.seriesTypes.scatter.prototype.pointClass)
r(e.prototype,{dataLabelOnNull:t.dataLabelOnNull,isValid:t.isValid,setState:t.setState})
return e}))
e(t,"Series/Map/MapSeries.js",[t["Mixins/ColorMapSeries.js"],t["Core/Globals.js"],t["Mixins/LegendSymbol.js"],t["Maps/Map.js"],t["Series/Map/MapPoint.js"],t["Core/Color/Palette.js"],t["Core/Series/Series.js"],t["Core/Series/SeriesRegistry.js"],t["Core/Renderer/SVG/SVGRenderer.js"],t["Core/Utilities.js"]],(function(t,e,i,o,r,s,n,a,l,p){var h=this&&this.__extends||function(){var t=function(e,i){t=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)e.hasOwnProperty(i)&&(t[i]=e[i])}
return t(e,i)}
return function(e,i){function o(){this.constructor=e}t(e,i)
e.prototype=null===i?Object.create(i):(o.prototype=i.prototype,new o)}}()
t=t.colorMapSeriesMixin
var c=e.noop,u=o.maps,d=o.splitPath,f=(o=a.seriesTypes).column,m=o.scatter
o=p.extend
var y=p.fireEvent,g=p.getNestedProperty,b=p.isArray,x=p.isNumber,v=p.merge,M=p.objectEach,C=p.pick,A=p.splat
p=function(t){function i(){var e=null!==t&&t.apply(this,arguments)||this
e.baseTrans=void 0
e.chart=void 0
e.data=void 0
e.group=void 0
e.joinBy=void 0
e.options=void 0
e.points=void 0
e.transformGroup=void 0
return e}h(i,t)
i.prototype.animate=function(t){var e=this.options.animation,i=this.group,o=this.xAxis,r=this.yAxis,s=o.pos,n=r.pos
this.chart.renderer.isSVG&&(!0===e&&(e={duration:1e3}),t?i.attr({translateX:s+o.len/2,translateY:n+r.len/2,scaleX:.001,scaleY:.001}):i.animate({translateX:s,translateY:n,scaleX:1,scaleY:1},e))}
i.prototype.animateDrilldown=function(t){var e=this.chart.plotBox,i=this.chart.drilldownLevels[this.chart.drilldownLevels.length-1],o=i.bBox,r=this.chart.options.drilldown.animation
t||(t=Math.min(o.width/e.width,o.height/e.height),i.shapeArgs={scaleX:t,scaleY:t,translateX:o.x,translateY:o.y},this.points.forEach((function(t){t.graphic&&t.graphic.attr(i.shapeArgs).animate({scaleX:1,scaleY:1,translateX:0,translateY:0},r)})))}
i.prototype.animateDrillupFrom=function(t){f.prototype.animateDrillupFrom.call(this,t)}
i.prototype.animateDrillupTo=function(t){f.prototype.animateDrillupTo.call(this,t)}
i.prototype.doFullTranslate=function(){return this.isDirtyData||this.chart.isResizing||this.chart.renderer.isVML||!this.baseTrans}
i.prototype.drawMapDataLabels=function(){n.prototype.drawDataLabels.call(this)
this.dataLabelsGroup&&this.dataLabelsGroup.clip(this.chart.clipRect)}
i.prototype.drawPoints=function(){var t=this,e=t.xAxis,i=t.yAxis,o=t.group,r=t.chart,s=r.renderer,n=this.baseTrans
t.transformGroup||(t.transformGroup=s.g().attr({scaleX:1,scaleY:1}).add(o),t.transformGroup.survive=!0)
if(t.doFullTranslate())r.hasRendered&&!r.styledMode&&t.points.forEach((function(e){e.shapeArgs&&(e.shapeArgs.fill=t.pointAttribs(e,e.state).fill)})),t.group=t.transformGroup,f.prototype.drawPoints.apply(t),t.group=o,t.points.forEach((function(e){if(e.graphic){var i=""
e.name&&(i+="highcharts-name-"+e.name.replace(/ /g,"-").toLowerCase())
e.properties&&e.properties["hc-key"]&&(i+=" highcharts-key-"+e.properties["hc-key"].toLowerCase())
i&&e.graphic.addClass(i)
r.styledMode&&e.graphic.css(t.pointAttribs(e,e.selected?"select":void 0))}})),this.baseTrans={originX:e.min-e.minPixelPadding/e.transA,originY:i.min-i.minPixelPadding/i.transA+(i.reversed?0:i.len/i.transA),transAX:e.transA,transAY:i.transA},this.transformGroup.animate({translateX:0,translateY:0,scaleX:1,scaleY:1})
else{var a=e.transA/n.transAX,l=i.transA/n.transAY,p=e.toPixels(n.originX,!0),h=i.toPixels(n.originY,!0);.99<a&&1.01>a&&.99<l&&1.01>l&&(l=a=1,p=Math.round(p),h=Math.round(h))
var c=this.transformGroup
if(r.renderer.globalAnimation){var u=c.attr("translateX"),d=c.attr("translateY"),m=c.attr("scaleX"),y=c.attr("scaleY")
c.attr({animator:0}).animate({animator:1},{step:function(t,e){c.attr({translateX:u+(p-u)*e.pos,translateY:d+(h-d)*e.pos,scaleX:m+(a-m)*e.pos,scaleY:y+(l-y)*e.pos})}})}else c.attr({translateX:p,translateY:h,scaleX:a,scaleY:l})}r.styledMode||o.element.setAttribute("stroke-width",C(t.options[t.pointAttrToOptions&&t.pointAttrToOptions["stroke-width"]||"borderWidth"],1)/(a||1))
this.drawMapDataLabels()}
i.prototype.getBox=function(t){var e,i=Number.MAX_VALUE,o=-i,r=i,s=-i,n=i,a=i,p=this.xAxis,h=this.yAxis;(t||[]).forEach((function(t){if(t.path){"string"==typeof t.path?t.path=d(t.path):"M"===t.path[0]&&(t.path=l.prototype.pathToSegments(t.path))
var p=t.path||[],h=-i,c=i,u=-i,f=i,m=t.properties
t._foundBox||(p.forEach((function(t){var e=t[t.length-2]
t=t[t.length-1]
"number"==typeof e&&"number"==typeof t&&(c=Math.min(c,e),h=Math.max(h,e),f=Math.min(f,t),u=Math.max(u,t))})),t._midX=c+(h-c)*C(t.middleX,m&&m["hc-middle-x"],.5),t._midY=f+(u-f)*C(t.middleY,m&&m["hc-middle-y"],.5),t._maxX=h,t._minX=c,t._maxY=u,t._minY=f,t.labelrank=C(t.labelrank,(h-c)*(u-f)),t._foundBox=!0)
o=Math.max(o,t._maxX)
r=Math.min(r,t._minX)
s=Math.max(s,t._maxY)
n=Math.min(n,t._minY)
a=Math.min(t._maxX-t._minX,t._maxY-t._minY,a)
e=!0}}))
e&&(this.minY=Math.min(n,C(this.minY,i)),this.maxY=Math.max(s,C(this.maxY,-i)),this.minX=Math.min(r,C(this.minX,i)),this.maxX=Math.max(o,C(this.maxX,-i)),p&&void 0===p.options.minRange&&(p.minRange=Math.min(5*a,(this.maxX-this.minX)/5,p.minRange||i)),h&&void 0===h.options.minRange&&(h.minRange=Math.min(5*a,(this.maxY-this.minY)/5,h.minRange||i)))}
i.prototype.getExtremes=function(){var t=n.prototype.getExtremes.call(this,this.valueData),e=t.dataMin
t=t.dataMax
this.chart.hasRendered&&this.isDirtyData&&this.getBox(this.options.data)
x(e)&&(this.valueMin=e)
x(t)&&(this.valueMax=t)
return{dataMin:this.minY,dataMax:this.maxY}}
i.prototype.hasData=function(){return!!this.processedXData.length}
i.prototype.pointAttribs=function(t,e){(e=t.series.chart.styledMode?this.colorAttribs(t):f.prototype.pointAttribs.call(this,t,e))["stroke-width"]=C(t.options[this.pointAttrToOptions&&this.pointAttrToOptions["stroke-width"]||"borderWidth"],"inherit")
return e}
i.prototype.render=function(){var t=this,e=n.prototype.render
t.chart.renderer.isVML&&3e3<t.data.length?setTimeout((function(){e.call(t)})):e.call(t)}
i.prototype.setData=function(t,i,o,s){var a=this.options,l=this.chart.options.chart,p=l&&l.map,h=a.mapData,c=this.joinBy,d=a.keys||this.pointArrayMap,f=[],m={},y=this.chart.mapTransforms
!h&&p&&(h="string"==typeof p?u[p]:p)
t&&t.forEach((function(e,i){var o=0
if(x(e))t[i]={value:e}
else if(b(e)){t[i]={}
!a.keys&&e.length>d.length&&"string"==typeof e[0]&&(t[i]["hc-key"]=e[0],++o)
for(var s=0;s<d.length;++s,++o)d[s]&&void 0!==e[o]&&(0<d[s].indexOf(".")?r.prototype.setNestedProperty(t[i],e[o],d[s]):t[i][d[s]]=e[o])}c&&"_i"===c[0]&&(t[i]._i=i)}))
this.getBox(t);(this.chart.mapTransforms=y=l&&l.mapTransforms||h&&h["hc-transform"]||y)&&M(y,(function(t){t.rotation&&(t.cosAngle=Math.cos(t.rotation),t.sinAngle=Math.sin(t.rotation))}))
if(h){"FeatureCollection"===h.type&&(this.mapTitle=h.title,h=e.geojson(h,this.type,this))
this.mapData=h
this.mapMap={}
for(y=0;y<h.length;y++)p=(l=h[y]).properties,l._i=y,c[0]&&p&&p[c[0]]&&(l[c[0]]=p[c[0]]),m[l[c[0]]]=l
this.mapMap=m
if(t&&c[1]){var C=c[1]
t.forEach((function(t){t=g(C,t)
m[t]&&f.push(m[t])}))}if(a.allAreas){this.getBox(h)
t=t||[]
if(c[1]){var A=c[1]
t.forEach((function(t){f.push(g(A,t))}))}f="|"+f.map((function(t){return t&&t[c[0]]})).join("|")+"|"
h.forEach((function(e){c[0]&&-1!==f.indexOf("|"+e[c[0]]+"|")||(t.push(v(e,{value:null})),s=!1)}))}else this.getBox(f)}n.prototype.setData.call(this,t,i,o,s)}
i.prototype.setOptions=function(t){var e=(t=n.prototype.setOptions.call(this,t)).joinBy
null===e&&(e="_i");(e=this.joinBy=A(e))[1]||(e[1]=e[0])
return t}
i.prototype.translate=function(){var t=this,e=t.xAxis,i=t.yAxis,o=t.doFullTranslate()
t.generatePoints()
t.data.forEach((function(r){x(r._midX)&&x(r._midY)&&(r.plotX=e.toPixels(r._midX,!0),r.plotY=i.toPixels(r._midY,!0))
o&&(r.shapeType="path",r.shapeArgs={d:t.translatePath(r.path)})}))
y(t,"afterTranslate")}
i.prototype.translatePath=function(t){var e=this.xAxis,i=this.yAxis,o=e.min,r=e.transA,s=e.minPixelPadding,n=i.min,a=i.transA,l=i.minPixelPadding,p=[]
t&&t.forEach((function(t){"M"===t[0]?p.push(["M",(t[1]-(o||0))*r+s,(t[2]-(n||0))*a+l]):"L"===t[0]?p.push(["L",(t[1]-(o||0))*r+s,(t[2]-(n||0))*a+l]):"C"===t[0]?p.push(["C",(t[1]-(o||0))*r+s,(t[2]-(n||0))*a+l,(t[3]-(o||0))*r+s,(t[4]-(n||0))*a+l,(t[5]-(o||0))*r+s,(t[6]-(n||0))*a+l]):"Q"===t[0]?p.push(["Q",(t[1]-(o||0))*r+s,(t[2]-(n||0))*a+l,(t[3]-(o||0))*r+s,(t[4]-(n||0))*a+l]):"Z"===t[0]&&p.push(["Z"])}))
return p}
i.defaultOptions=v(m.defaultOptions,{animation:!1,dataLabels:{crop:!1,formatter:function(){return this.point.value},inside:!0,overflow:!1,padding:0,verticalAlign:"middle"},marker:null,nullColor:s.neutralColor3,stickyTracking:!1,tooltip:{followPointer:!0,pointFormat:"{point.name}: {point.value}<br/>"},turboThreshold:0,allAreas:!0,borderColor:s.neutralColor20,borderWidth:1,joinBy:"hc-key",states:{hover:{halo:null,brightness:.2},normal:{animation:!0},select:{color:s.neutralColor20},inactive:{opacity:1}}})
return i}(m)
o(p.prototype,{type:"map",axisTypes:t.axisTypes,colorAttribs:t.colorAttribs,colorKey:t.colorKey,directTouch:!0,drawDataLabels:c,drawGraph:c,drawLegendSymbol:i.drawRectangle,forceDL:!0,getExtremesFromAll:!0,getSymbol:t.getSymbol,parallelArrays:t.parallelArrays,pointArrayMap:t.pointArrayMap,pointClass:r,preserveAspectRatio:!0,searchPoint:c,trackerGroups:t.trackerGroups,useMapGeometry:!0})
a.registerSeriesType("map",p)
return p}))
e(t,"Series/MapLine/MapLineSeries.js",[t["Series/Map/MapSeries.js"],t["Core/Series/SeriesRegistry.js"],t["Core/Utilities.js"]],(function(t,e,i){var o=this&&this.__extends||function(){var t=function(e,i){t=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)e.hasOwnProperty(i)&&(t[i]=e[i])}
return t(e,i)}
return function(e,i){function o(){this.constructor=e}t(e,i)
e.prototype=null===i?Object.create(i):(o.prototype=i.prototype,new o)}}(),r=e.series,s=i.extend,n=i.merge
i=function(e){function i(){var t=null!==e&&e.apply(this,arguments)||this
t.data=void 0
t.options=void 0
t.points=void 0
return t}o(i,e)
i.prototype.pointAttribs=function(e,i){(e=t.prototype.pointAttribs.call(this,e,i)).fill=this.options.fillColor
return e}
i.defaultOptions=n(t.defaultOptions,{lineWidth:1,fillColor:"none"})
return i}(t)
s(i.prototype,{type:"mapline",colorProp:"stroke",drawLegendSymbol:r.prototype.drawLegendSymbol,pointAttrToOptions:{stroke:"color","stroke-width":"lineWidth"}})
e.registerSeriesType("mapline",i)
return i}))
e(t,"Series/MapPoint/MapPointPoint.js",[t["Core/Series/SeriesRegistry.js"],t["Core/Utilities.js"]],(function(t,e){var i=this&&this.__extends||function(){var t=function(e,i){return(t=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)e.hasOwnProperty(i)&&(t[i]=e[i])})(e,i)}
return function(e,i){function o(){this.constructor=e}t(e,i)
e.prototype=null===i?Object.create(i):(o.prototype=i.prototype,new o)}}(),o=e.merge
return function(t){function e(){var e=null!==t&&t.apply(this,arguments)||this
e.options=void 0
e.series=void 0
return e}i(e,t)
e.prototype.applyOptions=function(e,i){e=void 0!==e.lat&&void 0!==e.lon?o(e,this.series.chart.fromLatLonToPoint(e)):e
return t.prototype.applyOptions.call(this,e,i)}
return e}(t.seriesTypes.scatter.prototype.pointClass)}))
e(t,"Series/MapPoint/MapPointSeries.js",[t["Series/MapPoint/MapPointPoint.js"],t["Core/Color/Palette.js"],t["Core/Series/SeriesRegistry.js"],t["Core/Utilities.js"]],(function(t,e,i,o){var r=this&&this.__extends||function(){var t=function(e,i){t=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)e.hasOwnProperty(i)&&(t[i]=e[i])}
return t(e,i)}
return function(e,i){function o(){this.constructor=e}t(e,i)
e.prototype=null===i?Object.create(i):(o.prototype=i.prototype,new o)}}(),s=i.seriesTypes.scatter,n=o.extend,a=o.merge
o=function(t){function i(){var e=null!==t&&t.apply(this,arguments)||this
e.data=void 0
e.options=void 0
e.points=void 0
return e}r(i,t)
i.prototype.drawDataLabels=function(){t.prototype.drawDataLabels.call(this)
this.dataLabelsGroup&&this.dataLabelsGroup.clip(this.chart.clipRect)}
i.defaultOptions=a(s.defaultOptions,{dataLabels:{crop:!1,defer:!1,enabled:!0,formatter:function(){return this.point.name},overflow:!1,style:{color:e.neutralColor100}}})
return i}(s)
n(o.prototype,{type:"mappoint",forceDL:!0,pointClass:t})
i.registerSeriesType("mappoint",o)
return o}))
e(t,"Series/Bubble/BubblePoint.js",[t["Core/Series/Point.js"],t["Core/Series/SeriesRegistry.js"],t["Core/Utilities.js"]],(function(t,e,i){var o=this&&this.__extends||function(){var t=function(e,i){return(t=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)e.hasOwnProperty(i)&&(t[i]=e[i])})(e,i)}
return function(e,i){function o(){this.constructor=e}t(e,i)
e.prototype=null===i?Object.create(i):(o.prototype=i.prototype,new o)}}()
i=i.extend
e=function(e){function i(){var t=null!==e&&e.apply(this,arguments)||this
t.options=void 0
t.series=void 0
return t}o(i,e)
i.prototype.haloPath=function(e){return t.prototype.haloPath.call(this,0===e?0:(this.marker&&this.marker.radius||0)+e)}
return i}(e.seriesTypes.scatter.prototype.pointClass)
i(e.prototype,{ttBelow:!1})
return e}))
e(t,"Series/Bubble/BubbleLegend.js",[t["Core/Chart/Chart.js"],t["Core/Color/Color.js"],t["Core/Globals.js"],t["Core/Legend.js"],t["Core/Color/Palette.js"],t["Core/Series/Series.js"],t["Core/Utilities.js"]],(function(t,e,i,o,r,s,n){var a=e.parse,l=i.noop
e=n.addEvent
var p=n.arrayMax,h=n.arrayMin,c=n.isNumber,u=n.merge,d=n.objectEach,f=n.pick,m=n.setOptions,y=n.stableSort,g=n.wrap
m({legend:{bubbleLegend:{borderColor:void 0,borderWidth:2,className:void 0,color:void 0,connectorClassName:void 0,connectorColor:void 0,connectorDistance:60,connectorWidth:1,enabled:!1,labels:{className:void 0,allowOverlap:!1,format:"",formatter:void 0,align:"right",style:{fontSize:10,color:void 0},x:0,y:0},maxSize:60,minSize:10,legendIndex:0,ranges:{value:void 0,borderColor:void 0,color:void 0,connectorColor:void 0},sizeBy:"area",sizeByAbsoluteValue:!1,zIndex:1,zThreshold:0}}})
m=function(){function t(t,e){this.options=this.symbols=this.visible=this.ranges=this.movementX=this.maxLabel=this.legendSymbol=this.legendItemWidth=this.legendItemHeight=this.legendItem=this.legendGroup=this.legend=this.fontMetrics=this.chart=void 0
this.setState=l
this.init(t,e)}t.prototype.init=function(t,e){this.options=t
this.visible=!0
this.chart=e.chart
this.legend=e}
t.prototype.addToLegend=function(t){t.splice(this.options.legendIndex,0,this)}
t.prototype.drawLegendSymbol=function(t){var e=this.chart,i=this.options,o=f(t.options.itemDistance,20),r=i.ranges,s=i.connectorDistance
this.fontMetrics=e.renderer.fontMetrics(i.labels.style.fontSize.toString()+"px")
r&&r.length&&c(r[0].value)?(y(r,(function(t,e){return e.value-t.value})),this.ranges=r,this.setOptions(),this.render(),e=this.getMaxLabelSize(),t=2*(r=this.ranges[0].radius),s=0<(s=s-r+e.width)?s:0,this.maxLabel=e,this.movementX="left"===i.labels.align?s:0,this.legendItemWidth=t+s+o,this.legendItemHeight=t+this.fontMetrics.h/2):t.options.bubbleLegend.autoRanges=!0}
t.prototype.setOptions=function(){var t=this.ranges,e=this.options,i=this.chart.series[e.seriesIndex],o=this.legend.baseline,r={"z-index":e.zIndex,"stroke-width":e.borderWidth},s={"z-index":e.zIndex,"stroke-width":e.connectorWidth},n=this.getLabelStyles(),l=i.options.marker.fillOpacity,p=this.chart.styledMode
t.forEach((function(h,c){p||(r.stroke=f(h.borderColor,e.borderColor,i.color),r.fill=f(h.color,e.color,1!==l?a(i.color).setOpacity(l).get("rgba"):i.color),s.stroke=f(h.connectorColor,e.connectorColor,i.color))
t[c].radius=this.getRangeRadius(h.value)
t[c]=u(t[c],{center:t[0].radius-t[c].radius+o})
p||u(!0,t[c],{bubbleStyle:u(!1,r),connectorStyle:u(!1,s),labelStyle:n})}),this)}
t.prototype.getLabelStyles=function(){var t=this.options,e={},i="left"===t.labels.align,o=this.legend.options.rtl
d(t.labels.style,(function(t,i){"color"!==i&&"fontSize"!==i&&"z-index"!==i&&(e[i]=t)}))
return u(!1,e,{"font-size":t.labels.style.fontSize,fill:f(t.labels.style.color,r.neutralColor100),"z-index":t.zIndex,align:o||i?"right":"left"})}
t.prototype.getRangeRadius=function(t){var e=this.options
return this.chart.series[this.options.seriesIndex].getRadius.call(this,e.ranges[e.ranges.length-1].value,e.ranges[0].value,e.minSize,e.maxSize,t)}
t.prototype.render=function(){var t=this.chart.renderer,e=this.options.zThreshold
this.symbols||(this.symbols={connectors:[],bubbleItems:[],labels:[]})
this.legendSymbol=t.g("bubble-legend")
this.legendItem=t.g("bubble-legend-item")
this.legendSymbol.translateX=0
this.legendSymbol.translateY=0
this.ranges.forEach((function(t){t.value>=e&&this.renderRange(t)}),this)
this.legendSymbol.add(this.legendItem)
this.legendItem.add(this.legendGroup)
this.hideOverlappingLabels()}
t.prototype.renderRange=function(t){var e=this.options,i=e.labels,o=this.chart.renderer,r=this.symbols,s=r.labels,n=t.center,a=Math.abs(t.radius),l=e.connectorDistance||0,p=i.align,h=i.style.fontSize
l=this.legend.options.rtl||"left"===p?-l:l
i=e.connectorWidth
var c=this.ranges[0].radius||0,u=n-a-e.borderWidth/2+i/2
h=h/2-(this.fontMetrics.h-h)/2
var d=o.styledMode
"center"===p&&(l=0,e.connectorDistance=0,t.labelStyle.align="center")
p=u+e.labels.y
var f=c+l+e.labels.x
r.bubbleItems.push(o.circle(c,n+((u%1?1:.5)-(i%2?0:.5)),a).attr(d?{}:t.bubbleStyle).addClass((d?"highcharts-color-"+this.options.seriesIndex+" ":"")+"highcharts-bubble-legend-symbol "+(e.className||"")).add(this.legendSymbol))
r.connectors.push(o.path(o.crispLine([["M",c,u],["L",c+l,u]],e.connectorWidth)).attr(d?{}:t.connectorStyle).addClass((d?"highcharts-color-"+this.options.seriesIndex+" ":"")+"highcharts-bubble-legend-connectors "+(e.connectorClassName||"")).add(this.legendSymbol))
t=o.text(this.formatLabel(t),f,p+h).attr(d?{}:t.labelStyle).addClass("highcharts-bubble-legend-labels "+(e.labels.className||"")).add(this.legendSymbol)
s.push(t)
t.placed=!0
t.alignAttr={x:f,y:p+h}}
t.prototype.getMaxLabelSize=function(){var t,e
this.symbols.labels.forEach((function(i){e=i.getBBox(!0)
t=t?e.width>t.width?e:t:e}))
return t||{}}
t.prototype.formatLabel=function(t){var e=this.options,i=e.labels.formatter
e=e.labels.format
var o=this.chart.numberFormatter
return e?n.format(e,t):i?i.call(t):o(t.value,1)}
t.prototype.hideOverlappingLabels=function(){var t=this.chart,e=this.symbols
!this.options.labels.allowOverlap&&e&&(t.hideOverlappingLabels(e.labels),e.labels.forEach((function(t,i){t.newOpacity?t.newOpacity!==t.oldOpacity&&e.connectors[i].show():e.connectors[i].hide()})))}
t.prototype.getRanges=function(){var t,e=this.legend.bubbleLegend,i=e.options.ranges,o=Number.MAX_VALUE,r=-Number.MAX_VALUE
e.chart.series.forEach((function(e){e.isBubble&&!e.ignoreSeries&&((t=e.zData.filter(c)).length&&(o=f(e.options.zMin,Math.min(o,Math.max(h(t),!1===e.options.displayNegative?e.options.zThreshold:-Number.MAX_VALUE))),r=f(e.options.zMax,Math.max(r,p(t)))))}))
var s=o===r?[{value:r}]:[{value:o},{value:(o+r)/2},{value:r,autoRanges:!0}]
i.length&&i[0].radius&&s.reverse()
s.forEach((function(t,e){i&&i[e]&&(s[e]=u(!1,i[e],t))}))
return s}
t.prototype.predictBubbleSizes=function(){var t=this.chart,e=this.fontMetrics,i=t.legend.options,o="horizontal"===i.layout,r=o?t.legend.lastLineHeight:0,s=t.plotSizeX,n=t.plotSizeY,a=t.series[this.options.seriesIndex]
t=Math.ceil(a.minPxSize)
var l=Math.ceil(a.maxPxSize)
a=a.options.maxSize
var p=Math.min(n,s);(i.floating||!/%$/.test(a)||(a=parseFloat(a),e=(p+r-e.h/2)*a/100/(a/100+1),o&&n-e>=s||!o&&s-e>=n))&&(e=l)
return[t,Math.ceil(e)]}
t.prototype.updateRanges=function(t,e){var i=this.legend.options.bubbleLegend
i.minSize=t
i.maxSize=e
i.ranges=this.getRanges()}
t.prototype.correctSizes=function(){var t=this.legend,e=this.chart.series[this.options.seriesIndex]
1<Math.abs(Math.ceil(e.maxPxSize)-this.options.maxSize)&&(this.updateRanges(this.options.minSize,e.maxPxSize),t.render())}
return t}()
e(o,"afterGetAllItems",(function(t){var e=this.bubbleLegend,o=this.options,r=o.bubbleLegend,s=this.chart.getVisibleBubbleSeriesIndex()
e&&e.ranges&&e.ranges.length&&(r.ranges.length&&(r.autoRanges=!!r.ranges[0].autoRanges),this.destroyItem(e))
0<=s&&o.enabled&&r.enabled&&(r.seriesIndex=s,this.bubbleLegend=new i.BubbleLegend(r,this),this.bubbleLegend.addToLegend(t.allItems))}))
t.prototype.getVisibleBubbleSeriesIndex=function(){for(var t=this.series,e=0;e<t.length;){if(t[e]&&t[e].isBubble&&t[e].visible&&t[e].zData.length)return e
e++}return-1}
o.prototype.getLinesHeights=function(){var t,e=this.allItems,i=[],o=e.length,r=0
for(t=0;t<o;t++)if(e[t].legendItemHeight&&(e[t].itemHeight=e[t].legendItemHeight),e[t]===e[o-1]||e[t+1]&&e[t]._legendItemPos[1]!==e[t+1]._legendItemPos[1]){i.push({height:0})
for(var s=i[i.length-1];r<=t;r++)e[r].itemHeight>s.height&&(s.height=e[r].itemHeight)
s.step=t}return i}
o.prototype.retranslateItems=function(t){var e,i,o,r=this.options.rtl,s=0
this.allItems.forEach((function(n,a){e=n.legendGroup.translateX
i=n._legendItemPos[1];((o=n.movementX)||r&&n.ranges)&&(o=r?e-n.options.maxSize/2:e+o,n.legendGroup.attr({translateX:o}))
a>t[s].step&&s++
n.legendGroup.attr({translateY:Math.round(i+t[s].height/2)})
n._legendItemPos[1]=i+t[s].height/2}))}
e(s,"legendItemClick",(function(){var t=this.chart,e=this.visible,i=this.chart.legend
i&&i.bubbleLegend&&(this.visible=!e,this.ignoreSeries=e,t=0<=t.getVisibleBubbleSeriesIndex(),i.bubbleLegend.visible!==t&&(i.update({bubbleLegend:{enabled:t}}),i.bubbleLegend.visible=t),this.visible=e)}))
g(t.prototype,"drawChartBox",(function(t,e,i){var o=this.legend,r=0<=this.getVisibleBubbleSeriesIndex()
if(o&&o.options.enabled&&o.bubbleLegend&&o.options.bubbleLegend.autoRanges&&r){var s=o.bubbleLegend.options
r=o.bubbleLegend.predictBubbleSizes()
o.bubbleLegend.updateRanges(r[0],r[1])
s.placed||(o.group.placed=!1,o.allItems.forEach((function(t){t.legendGroup.translateY=null})))
o.render()
this.getMargins()
this.axes.forEach((function(t){t.visible&&t.render()
s.placed||(t.setScale(),t.updateNames(),d(t.ticks,(function(t){t.isNew=!0
t.isNewLabel=!0})))}))
s.placed=!0
this.getMargins()
t.call(this,e,i)
o.bubbleLegend.correctSizes()
o.retranslateItems(o.getLinesHeights())}else t.call(this,e,i),o&&o.options.enabled&&o.bubbleLegend&&(o.render(),o.retranslateItems(o.getLinesHeights()))}))
i.BubbleLegend=m
return i.BubbleLegend}))
e(t,"Series/Bubble/BubbleSeries.js",[t["Core/Axis/Axis.js"],t["Series/Bubble/BubblePoint.js"],t["Core/Color/Color.js"],t["Core/Globals.js"],t["Core/Series/Series.js"],t["Core/Series/SeriesRegistry.js"],t["Core/Utilities.js"]],(function(t,e,i,o,r,s,n){var a=this&&this.__extends||function(){var t=function(e,i){t=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)e.hasOwnProperty(i)&&(t[i]=e[i])}
return t(e,i)}
return function(e,i){function o(){this.constructor=e}t(e,i)
e.prototype=null===i?Object.create(i):(o.prototype=i.prototype,new o)}}(),l=i.parse
i=o.noop
var p=s.seriesTypes
o=p.column
var h=p.scatter,c=n.arrayMax,u=n.arrayMin,d=n.clamp,f=n.extend,m=n.isNumber,y=n.merge,g=n.pick,b=n.pInt
n=function(t){function e(){var e=null!==t&&t.apply(this,arguments)||this
e.data=void 0
e.maxPxSize=void 0
e.minPxSize=void 0
e.options=void 0
e.points=void 0
e.radii=void 0
e.yData=void 0
e.zData=void 0
return e}a(e,t)
e.prototype.animate=function(t){!t&&this.points.length<this.options.animationLimit&&this.points.forEach((function(t){var e=t.graphic
e&&e.width&&(this.hasRendered||e.attr({x:t.plotX,y:t.plotY,width:1,height:1}),e.animate(this.markerAttribs(t),this.options.animation))}),this)}
e.prototype.getRadii=function(t,e,i){var o=this.zData,r=this.yData,s=i.minPxSize,n=i.maxPxSize,a=[],l=0
for(i=o.length;l<i;l++){var p=o[l]
a.push(this.getRadius(t,e,s,n,p,r[l]))}this.radii=a}
e.prototype.getRadius=function(t,e,i,o,r,s){var n=this.options,a="width"!==n.sizeBy,l=n.zThreshold,p=e-t,h=.5
if(null===s||null===r)return null
if(m(r)){n.sizeByAbsoluteValue&&(r=Math.abs(r-l),p=Math.max(e-l,Math.abs(t-l)),t=0)
if(r<t)return i/2-1
0<p&&(h=(r-t)/p)}a&&0<=h&&(h=Math.sqrt(h))
return Math.ceil(i+h*(o-i))/2}
e.prototype.hasData=function(){return!!this.processedXData.length}
e.prototype.pointAttribs=function(t,e){var i=this.options.marker.fillOpacity
t=r.prototype.pointAttribs.call(this,t,e)
1!==i&&(t.fill=l(t.fill).setOpacity(i).get("rgba"))
return t}
e.prototype.translate=function(){var e,i=this.data,o=this.radii
t.prototype.translate.call(this)
for(e=i.length;e--;){var r=i[e],s=o?o[e]:0
m(s)&&s>=this.minPxSize/2?(r.marker=f(r.marker,{radius:s,width:2*s,height:2*s}),r.dlBox={x:r.plotX-s,y:r.plotY-s,width:2*s,height:2*s}):r.shapeArgs=r.plotY=r.dlBox=void 0}}
e.defaultOptions=y(h.defaultOptions,{dataLabels:{formatter:function(){return this.point.z},inside:!0,verticalAlign:"middle"},animationLimit:250,marker:{lineColor:null,lineWidth:1,fillOpacity:.5,radius:null,states:{hover:{radiusPlus:0}},symbol:"circle"},minSize:8,maxSize:"20%",softThreshold:!1,states:{hover:{halo:{size:5}}},tooltip:{pointFormat:"({point.x}, {point.y}), Size: {point.z}"},turboThreshold:0,zThreshold:0,zoneAxis:"z"})
return e}(h)
f(n.prototype,{alignDataLabel:o.prototype.alignDataLabel,applyZones:i,bubblePadding:!0,buildKDTree:i,directTouch:!0,isBubble:!0,pointArrayMap:["y","z"],pointClass:e,parallelArrays:["x","y","z"],trackerGroups:["group","dataLabelsGroup"],specialGroup:"group",zoneAxis:"z"})
t.prototype.beforePadding=function(){var t=this,e=this.len,i=this.chart,o=0,r=e,s=this.isXAxis,n=s?"xData":"yData",a=this.min,l={},p=Math.min(i.plotWidth,i.plotHeight),h=Number.MAX_VALUE,f=-Number.MAX_VALUE,y=this.max-a,x=e/y,v=[]
this.series.forEach((function(e){var o=e.options
!e.bubblePadding||!e.visible&&i.options.chart.ignoreHiddenSeries||(t.allowZoomOutside=!0,v.push(e),s&&(["minSize","maxSize"].forEach((function(t){var e=o[t],i=/%$/.test(e)
e=b(e)
l[t]=i?p*e/100:e})),e.minPxSize=l.minSize,e.maxPxSize=Math.max(l.maxSize,l.minSize),(e=e.zData.filter(m)).length&&(h=g(o.zMin,d(u(e),!1===o.displayNegative?o.zThreshold:-Number.MAX_VALUE,h)),f=g(o.zMax,Math.max(f,c(e))))))}))
v.forEach((function(e){var i=e[n],l=i.length
s&&e.getRadii(h,f,e)
if(0<y)for(;l--;)if(m(i[l])&&t.dataMin<=i[l]&&i[l]<=t.max){var p=e.radii?e.radii[l]:0
o=Math.min((i[l]-a)*x-p,o)
r=Math.max((i[l]-a)*x+p,r)}}))
v.length&&0<y&&!this.logarithmic&&(r-=e,x*=(e+Math.max(0,o)-Math.min(r,e))/e,[["min","userMin",o],["max","userMax",r]].forEach((function(e){void 0===g(t.options[e[0]],t[e[1]])&&(t[e[0]]+=e[2]/x)})))}
s.registerSeriesType("bubble",n)
return n}))
e(t,"Series/MapBubble/MapBubblePoint.js",[t["Core/Series/SeriesRegistry.js"],t["Core/Utilities.js"]],(function(t,e){var i=this&&this.__extends||function(){var t=function(e,i){return(t=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)e.hasOwnProperty(i)&&(t[i]=e[i])})(e,i)}
return function(e,i){function o(){this.constructor=e}t(e,i)
e.prototype=null===i?Object.create(i):(o.prototype=i.prototype,new o)}}(),o=t.seriesTypes,r=o.map
t=e.extend
var s=e.merge
e=function(t){function e(){return null!==t&&t.apply(this,arguments)||this}i(e,t)
e.prototype.applyOptions=function(e,i){return e&&void 0!==e.lat&&void 0!==e.lon?t.prototype.applyOptions.call(this,s(e,this.series.chart.fromLatLonToPoint(e)),i):r.prototype.pointClass.prototype.applyOptions.call(this,e,i)}
e.prototype.isValid=function(){return"number"==typeof this.z}
return e}(o.bubble.prototype.pointClass)
t(e.prototype,{ttBelow:!1})
return e}))
e(t,"Series/MapBubble/MapBubbleSeries.js",[t["Series/Bubble/BubbleSeries.js"],t["Series/MapBubble/MapBubblePoint.js"],t["Series/Map/MapSeries.js"],t["Core/Series/SeriesRegistry.js"],t["Core/Utilities.js"]],(function(t,e,i,o,r){var s=this&&this.__extends||function(){var t=function(e,i){t=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)e.hasOwnProperty(i)&&(t[i]=e[i])}
return t(e,i)}
return function(e,i){function o(){this.constructor=e}t(e,i)
e.prototype=null===i?Object.create(i):(o.prototype=i.prototype,new o)}}(),n=r.extend,a=r.merge
r=function(e){function i(){var t=null!==e&&e.apply(this,arguments)||this
t.data=void 0
t.options=void 0
t.points=void 0
return t}s(i,e)
i.defaultOptions=a(t.defaultOptions,{animationLimit:500,tooltip:{pointFormat:"{point.name}: {point.z}"}})
return i}(t)
n(r.prototype,{type:"mapbubble",getBox:i.prototype.getBox,pointArrayMap:["z"],pointClass:e,setData:i.prototype.setData,setOptions:i.prototype.setOptions,xyFromShape:!0})
o.registerSeriesType("mapbubble",r)
return r}))
e(t,"Series/Heatmap/HeatmapPoint.js",[t["Mixins/ColorMapSeries.js"],t["Core/Series/SeriesRegistry.js"],t["Core/Utilities.js"]],(function(t,e,i){var o=this&&this.__extends||function(){var t=function(e,i){t=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)e.hasOwnProperty(i)&&(t[i]=e[i])}
return t(e,i)}
return function(e,i){function o(){this.constructor=e}t(e,i)
e.prototype=null===i?Object.create(i):(o.prototype=i.prototype,new o)}}()
t=t.colorMapPointMixin
var r=i.clamp,s=i.extend,n=i.pick
e=function(t){function e(){var e=null!==t&&t.apply(this,arguments)||this
e.options=void 0
e.series=void 0
e.value=void 0
e.x=void 0
e.y=void 0
return e}o(e,t)
e.prototype.applyOptions=function(e,i){(e=t.prototype.applyOptions.call(this,e,i)).formatPrefix=e.isNull||null===e.value?"null":"point"
return e}
e.prototype.getCellAttributes=function(){var t=this.series,e=t.options,i=(e.colsize||1)/2,o=(e.rowsize||1)/2,s=t.xAxis,a=t.yAxis,l=this.options.marker||t.options.marker
t=t.pointPlacementToXValue()
var p=n(this.pointPadding,e.pointPadding,0),h={x1:r(Math.round(s.len-(s.translate(this.x-i,!1,!0,!1,!0,-t)||0)),-s.len,2*s.len),x2:r(Math.round(s.len-(s.translate(this.x+i,!1,!0,!1,!0,-t)||0)),-s.len,2*s.len),y1:r(Math.round(a.translate(this.y-o,!1,!0,!1,!0)||0),-a.len,2*a.len),y2:r(Math.round(a.translate(this.y+o,!1,!0,!1,!0)||0),-a.len,2*a.len)};[["width","x"],["height","y"]].forEach((function(t){var e=t[0],i=(t=t[1])+"1",o=t+"2",r=Math.abs(h[i]-h[o]),s=l&&l.lineWidth||0,n=Math.abs(h[i]+h[o])/2
l[e]&&l[e]<r&&(h[i]=n-l[e]/2-s/2,h[o]=n+l[e]/2+s/2)
p&&("y"===t&&(i=o,o=t+"1"),h[i]+=p,h[o]-=p)}))
return h}
e.prototype.haloPath=function(t){if(!t)return[]
var e=this.shapeArgs
return["M",e.x-t,e.y-t,"L",e.x-t,e.y+e.height+t,e.x+e.width+t,e.y+e.height+t,e.x+e.width+t,e.y-t,"Z"]}
e.prototype.isValid=function(){return 1/0!==this.value&&-1/0!==this.value}
return e}(e.seriesTypes.scatter.prototype.pointClass)
s(e.prototype,{dataLabelOnNull:t.dataLabelOnNull,setState:t.setState})
return e}))
e(t,"Series/Heatmap/HeatmapSeries.js",[t["Mixins/ColorMapSeries.js"],t["Core/Globals.js"],t["Series/Heatmap/HeatmapPoint.js"],t["Mixins/LegendSymbol.js"],t["Core/Color/Palette.js"],t["Core/Series/SeriesRegistry.js"],t["Core/Renderer/SVG/SVGRenderer.js"],t["Core/Utilities.js"]],(function(t,e,i,o,r,s,n,a){var l=this&&this.__extends||function(){var t=function(e,i){t=Object.setPrototypeOf||{__proto__:[]}instanceof Array&&function(t,e){t.__proto__=e}||function(t,e){for(var i in e)e.hasOwnProperty(i)&&(t[i]=e[i])}
return t(e,i)}
return function(e,i){function o(){this.constructor=e}t(e,i)
e.prototype=null===i?Object.create(i):(o.prototype=i.prototype,new o)}}()
t=t.colorMapSeriesMixin
var p=e.noop,h=s.series,c=s.seriesTypes,u=c.column,d=c.scatter,f=n.prototype.symbols,m=a.extend,y=a.fireEvent,g=a.isNumber,b=a.merge,x=a.pick
n=function(t){function i(){var e=null!==t&&t.apply(this,arguments)||this
e.colorAxis=void 0
e.data=void 0
e.options=void 0
e.points=void 0
e.valueMax=NaN
e.valueMin=NaN
return e}l(i,t)
i.prototype.drawPoints=function(){var t=this;((this.options.marker||{}).enabled||this._hasPointMarkers)&&(h.prototype.drawPoints.call(this),this.points.forEach((function(e){e.graphic&&e.graphic[t.chart.styledMode?"css":"animate"](t.colorAttribs(e))})))}
i.prototype.getExtremes=function(){var t=h.prototype.getExtremes.call(this,this.valueData),e=t.dataMin
t=t.dataMax
g(e)&&(this.valueMin=e)
g(t)&&(this.valueMax=t)
return h.prototype.getExtremes.call(this)}
i.prototype.getValidPoints=function(t,e){return h.prototype.getValidPoints.call(this,t,e,!0)}
i.prototype.hasData=function(){return!!this.processedXData.length}
i.prototype.init=function(){h.prototype.init.apply(this,arguments)
var t=this.options
t.pointRange=x(t.pointRange,t.colsize||1)
this.yAxis.axisPointRange=t.rowsize||1
m(f,{ellipse:f.circle,rect:f.square})}
i.prototype.markerAttribs=function(t,e){var i=t.marker||{},o=this.options.marker||{},r=t.shapeArgs||{},s={}
if(t.hasImage)return{x:t.plotX,y:t.plotY}
if(e){var n=o.states[e]||{},a=i.states&&i.states[e]||{};[["width","x"],["height","y"]].forEach((function(t){s[t[0]]=(a[t[0]]||n[t[0]]||r[t[0]])+(a[t[0]+"Plus"]||n[t[0]+"Plus"]||0)
s[t[1]]=r[t[1]]+(r[t[0]]-s[t[0]])/2}))}return e?s:r}
i.prototype.pointAttribs=function(t,i){var o=h.prototype.pointAttribs.call(this,t,i),r=this.options||{},s=this.chart.options.plotOptions||{},n=s.series||{},a=s.heatmap||{}
s=r.borderColor||a.borderColor||n.borderColor
n=r.borderWidth||a.borderWidth||n.borderWidth||o["stroke-width"]
o.stroke=t&&t.marker&&t.marker.lineColor||r.marker&&r.marker.lineColor||s||this.color
o["stroke-width"]=n
i&&(i=(t=b(r.states[i],r.marker&&r.marker.states[i],t&&t.options.states&&t.options.states[i]||{})).brightness,o.fill=t.color||e.color(o.fill).brighten(i||0).get(),o.stroke=t.lineColor)
return o}
i.prototype.setClip=function(t){var e=this.chart
h.prototype.setClip.apply(this,arguments);(!1!==this.options.clip||t)&&this.markerGroup.clip((t||this.clipBox)&&this.sharedClipKey?e[this.sharedClipKey]:e.clipRect)}
i.prototype.translate=function(){var t=this.options,e=t.marker&&t.marker.symbol||"",i=f[e]?e:"rect"
t=this.options
var o=-1!==["circle","square"].indexOf(i)
this.generatePoints()
this.points.forEach((function(t){var r=t.getCellAttributes(),s={x:Math.min(r.x1,r.x2),y:Math.min(r.y1,r.y2),width:Math.max(Math.abs(r.x2-r.x1),0),height:Math.max(Math.abs(r.y2-r.y1),0)},n=t.hasImage=0===(t.marker&&t.marker.symbol||e||"").indexOf("url")
if(o){var a=Math.abs(s.width-s.height)
s.x=Math.min(r.x1,r.x2)+(s.width<s.height?0:a/2)
s.y=Math.min(r.y1,r.y2)+(s.width<s.height?a/2:0)
s.width=s.height=Math.min(s.width,s.height)}a={plotX:(r.x1+r.x2)/2,plotY:(r.y1+r.y2)/2,clientX:(r.x1+r.x2)/2,shapeType:"path",shapeArgs:b(!0,s,{d:f[i](s.x,s.y,s.width,s.height)})}
n&&(t.marker={width:s.width,height:s.height})
m(t,a)}))
y(this,"afterTranslate")}
i.defaultOptions=b(d.defaultOptions,{animation:!1,borderWidth:0,nullColor:r.neutralColor3,dataLabels:{formatter:function(){return this.point.value},inside:!0,verticalAlign:"middle",crop:!1,overflow:!1,padding:0},marker:{symbol:"rect",radius:0,lineColor:void 0,states:{hover:{lineWidthPlus:0},select:{}}},clip:!0,pointRange:null,tooltip:{pointFormat:"{point.x}, {point.y}: {point.value}<br/>"},states:{hover:{halo:!1,brightness:.2}}})
return i}(d)
m(n.prototype,{alignDataLabel:u.prototype.alignDataLabel,axisTypes:t.axisTypes,colorAttribs:t.colorAttribs,colorKey:t.colorKey,directTouch:!0,drawLegendSymbol:o.drawRectangle,getBox:p,getExtremesFromAll:!0,getSymbol:h.prototype.getSymbol,hasPointSpecificOptions:!0,parallelArrays:t.parallelArrays,pointArrayMap:["y","value"],pointClass:i,trackerGroups:t.trackerGroups})
s.registerSeriesType("heatmap",n)
return n}))
e(t,"Extensions/GeoJSON.js",[t["Core/Chart/Chart.js"],t["Core/Globals.js"],t["Core/Utilities.js"]],(function(t,e,i){function o(t,e){var i,o=!1,r=t.x,s=t.y
t=0
for(i=e.length-1;t<e.length;i=t++){e[t][1]>s!==e[i][1]>s&&r<(e[i][0]-e[t][0])*(s-e[t][1])/(e[i][1]-e[t][1])+e[t][0]&&(o=!o)}return o}var r=e.win,s=i.error,n=i.extend,a=i.format,l=i.merge
i=i.wrap
t.prototype.transformFromLatLon=function(t,e){var i,o=(null===(i=this.userOptions.chart)||void 0===i?void 0:i.proj4)||r.proj4
if(!o)return s(21,!1,this),{x:0,y:null}
t=o(e.crs,[t.lon,t.lat])
i=e.cosAngle||e.rotation&&Math.cos(e.rotation)
o=e.sinAngle||e.rotation&&Math.sin(e.rotation)
return{x:(((t=e.rotation?[t[0]*i+t[1]*o,-t[0]*o+t[1]*i]:t)[0]-(e.xoffset||0))*(e.scale||1)+(e.xpan||0))*(e.jsonres||1)+(e.jsonmarginX||0),y:(((e.yoffset||0)-t[1])*(e.scale||1)+(e.ypan||0))*(e.jsonres||1)-(e.jsonmarginY||0)}}
t.prototype.transformToLatLon=function(t,e){if(void 0!==r.proj4){t={x:((t.x-(e.jsonmarginX||0))/(e.jsonres||1)-(e.xpan||0))/(e.scale||1)+(e.xoffset||0),y:((-t.y-(e.jsonmarginY||0))/(e.jsonres||1)+(e.ypan||0))/(e.scale||1)+(e.yoffset||0)}
var i=e.cosAngle||e.rotation&&Math.cos(e.rotation),o=e.sinAngle||e.rotation&&Math.sin(e.rotation)
return{lat:(e=r.proj4(e.crs,"WGS84",e.rotation?{x:t.x*i+t.y*-o,y:t.x*o+t.y*i}:t)).y,lon:e.x}}s(21,!1,this)}
t.prototype.fromPointToLatLon=function(t){var e,i=this.mapTransforms
if(i){for(e in i)if(Object.hasOwnProperty.call(i,e)&&i[e].hitZone&&o({x:t.x,y:-t.y},i[e].hitZone.coordinates[0]))return this.transformToLatLon(t,i[e])
return this.transformToLatLon(t,i.default)}s(22,!1,this)}
t.prototype.fromLatLonToPoint=function(t){var e,i=this.mapTransforms
if(!i)return s(22,!1,this),{x:0,y:null}
for(e in i)if(Object.hasOwnProperty.call(i,e)&&i[e].hitZone){var r=this.transformFromLatLon(t,i[e])
if(o({x:r.x,y:-r.y},i[e].hitZone.coordinates[0]))return r}return this.transformFromLatLon(t,i.default)}
e.geojson=function(t,e,i){var o=[],r=[],s=function(t){t.forEach((function(t,e){0===e?r.push(["M",t[0],-t[1]]):r.push(["L",t[0],-t[1]])}))}
e=e||"map"
t.features.forEach((function(t){var i,a=t.geometry,l=a.type
a=a.coordinates
t=t.properties
r=[]
"map"===e||"mapbubble"===e?("Polygon"===l?(a.forEach(s),r.push(["Z"])):"MultiPolygon"===l&&(a.forEach((function(t){t.forEach(s)})),r.push(["Z"])),r.length&&(i={path:r})):"mapline"===e?("LineString"===l?s(a):"MultiLineString"===l&&a.forEach(s),r.length&&(i={path:r})):"mappoint"===e&&"Point"===l&&(i={x:a[0],y:-a[1]})
i&&o.push(n(i,{name:t.name||t.NAME,properties:t}))}))
i&&t.copyrightShort&&(i.chart.mapCredits=a(i.chart.options.credits.mapText,{geojson:t}),i.chart.mapCreditsFull=a(i.chart.options.credits.mapTextFull,{geojson:t}))
return o}
i(t.prototype,"addCredits",(function(t,e){e=l(!0,this.options.credits,e)
this.mapCredits&&(e.href=null)
t.call(this,e)
this.credits&&this.mapCreditsFull&&this.credits.attr({title:this.mapCreditsFull})}))}))
e(t,"masters/modules/map.src.js",[],(function(){}))}))

//# sourceMappingURL=map.map