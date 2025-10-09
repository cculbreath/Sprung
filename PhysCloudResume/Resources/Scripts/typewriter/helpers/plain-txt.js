(function() {

	// Block helper function definitions.
	var txtHelpers = module.exports = {

		// A sample helper that returns the supplied value.
		wrapper: function(text, options) {
			const width = options.hash.width || 80
			const leftMargin = options.hash.leftMargin || 0
			const rightMargin = options.hash.rightMargin || 0
			const rightFill = options.hash.rightFill || false
			const centered = options.hash.centered || false

			// Calculate the effective line width for the text content
			const effectiveWidth = width - leftMargin - rightMargin

			// Function to wrap the text
			const wrapText = (str, maxWidth) => {
				const words = str.split(' ')
				let lines = []
				let currentLine = ''

				words.forEach(word => {
					if ((currentLine + word).length <= maxWidth) {
						currentLine += (currentLine ? ' ' : '') + word
					} else {
						lines.push(currentLine)
						currentLine = word
					}
				})

				if (currentLine) {
					lines.push(currentLine)
				}

				return lines
			}

			// Wrap the text and add margins
			const lines = wrapText(text, effectiveWidth)
			const formattedLines = lines.map(line => {
				let formattedLine = ' '.repeat(leftMargin) + line

				if (centered) {
					const totalPadding = width - line.length
					const leftPadding = Math.floor(totalPadding / 2)
					const rightPadding = totalPadding - leftPadding
					formattedLine = ' '.repeat(leftPadding) + line + ' '.repeat(rightPadding)
				} else {
					if (rightFill) {
						formattedLine = formattedLine.padEnd(width, ' ')
					}
				}

				return formattedLine
			})


			const formattedText = formattedLines.join('\n')

			return formattedText
		},
		joiner: function(array, separator, options) {
			return array.join(separator)
		},
		myLogger: function(txt, options) {
			Object.keys(txt).forEach(key => {
			});		},
		sectionLine: function(title, options) {
			const stripTags = function stripTags(html) {
			    return html.replace(/<\/?[^>]+(>|$)|↪/g, "");
			}

			
			title = stripTags(title)
			const width = options.hash.width || 80
			const titleLength = title.length

			// Calculate the padding and dashes
			const totalDashes = width - titleLength - 4 // 4 accounts for the '*' and spaces around the title
			const leftDashes = Math.floor(totalDashes / 2)
			const rightDashes = totalDashes - leftDashes

			// Construct the separator line
			const separatorLine = `*${'-'.repeat(leftDashes)} ${title.toUpperCase()} ${'-'.repeat(rightDashes)}*`
			return separatorLine
		},
		jobString: function(employer, location, start, end, options) {
			let strA = `${employer} | ${location}`
			let strB = `${(start.trim().split(' '))[1]} – ${(end.trim().split(' '))[1]}`
			const width = options.hash.width || 80
			const spaceBetween = width - strA.length - strB.length

			if (spaceBetween < 0) {
				throw new Error('Total length of strA and strB exceeds the specified width')

			}

			const formattedLine = `${strA}${' '.repeat(spaceBetween)}${strB}`
			return formattedLine
		},
		bulletText: function(text, options) {
			const marginLeft = options.hash.marginLeft
			const width = options.hash.width || 79
			const bullet = options.hash.bullet || '*'
			const textWidth = width - marginLeft - bullet.length - 1 // 1 for the space after bullet

			// Function to wrap the text
			const wrapText = (str, maxWidth) => {
				const words = str.split(' ')
				let lines = []
				let currentLine = ''

				words.forEach(word => {
					if ((currentLine + word).length <= maxWidth) {
						currentLine += (currentLine ? ' ' : '') + word
					} else {
						lines.push(currentLine)
						currentLine = word
					}
				})

				if (currentLine) {
					lines.push(currentLine)
				}

				return lines
			}

			// Wrap the text
			const lines = wrapText(text, textWidth)
			// Add bullet to the first line and left margin to subsequent lines
			const formattedLines = lines.map((line, index) => {
				if (index === 0) {
					if (marginLeft === 0) return `${bullet.trim()} ${line}`
					else return `${' '.repeat(marginLeft)}${bullet} ${line}`
				} else {
					return `${' '.repeat(marginLeft + bullet.length + 1)}${line}`
				}
			})
			const formattedText = formattedLines.join('\n')
			return formattedText
		},
		formatCitation: function(entry) {
			let result = ''

			if (entry.type === 'article') {

				const authors = entry.authors.map(author => {
					const parts = author.split(' ')
					const lastName = parts.pop()
					const initials = parts.map(name => name.charAt(0) + '.').join(' ')
					return `${lastName}, ${initials}`
				}).join(', ')
				result = `
      ${authors}. "${entry.title}". ${entry.journal}, ${entry.volume}(${entry.issue}), ${entry.pages}. (${entry.year})
    `
			} else if (entry.type === 'dissertation') {
				result = `
      ${entry.authors}. "${entry.title}". ${entry.journal}. Doctoral Dissertation. (${entry.year})
    `
			}

			return result.trim()
		},
		json: function(obj) {

			return JSON.stringify(obj, null, 2); // pretty-print with indentation

		},
		wrapBlurb: function(context, options) {
			// Create an array to hold all the text segments
			let combinedText = '';

			// Loop through each project and hobby to append the title and its examples
			context.forEach(project => {
				// Start with the title
				combinedText += `[${project.title}] `;

				// Append each sec and blurb pair
				project.examples.forEach(example => {
					let exampleName = example.name;
					if (exampleName.charAt(exampleName.length - 1) === ':') {
					    exampleName = exampleName.slice(0, -1); // Remove trailing colon
					}
					combinedText += `*${exampleName}* ${example.description} `;
								});
			});

			// Apply an 80-character wrap to the resulting string
			let wrappedText = '';
			let currentLine = '';

			combinedText.split(' ').forEach(word => {
				if ((currentLine + word).length > 80) {
					wrappedText += currentLine.trim() + '\n';
					currentLine = '';
				}
				currentLine += word + ' ';
			});

			wrappedText += currentLine.trim(); // Add the last line

			return wrappedText;
		}
	}
}).call(this)
