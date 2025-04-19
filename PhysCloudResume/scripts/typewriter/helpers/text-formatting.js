
/**
Sample helper definitions for HackMyResume's "basis" example theme.
@license MIT. See LICENSE.md for details.
@module themes/basis/helpers/sample-helpers
*/


(function() {

  // Block helper function definitions.
  var SampleHelpers = module.exports = {

    // A sample helper that returns the supplied value.
    nonBreakingSpaces: function(str, options) {
      return str.replace(/\s/g, '&nbsp;')
    },

    // Another sample helper that returns the supplied value.
    andToAmpersand: function(str, options) {
      return str.replace(/&|and/g, '&amp;')
    },

    // A sample block helper

    articleType: function(type, options) {
      return (type === 'article')
    },
    dissType: function(type, options) {
      return (type === 'dissertation')
    },
    formatAuthors: function(authors, options) {
      return authors.map(author => {
        const parts = author.split(' ');
        const lastName = parts.pop();
        const initials = parts.map(name => name.charAt(0) + '.').join('&nbsp;');
        return `${lastName}, ${initials}`;
      }).join(', ');
    },
	footer: function(contact) {
		console.log(contact)
		let string = `
		@page :first{
		  @bottom-center{
			content:  '${contact.name} * ${contact.location.city}, ${contact.location.state} * ${contact.phone} * ${contact.email} * ${contact.website}';
		    border: black 1px solid;
		    text-align: center;
		    padding: 2px 8px;
		    background-color: white;
		    font-family: 'CMU Typewriter Text';
		    font-weight: 200;
		    font-size: 10pt;
			margin-bottom: 30px;
			padding: 0px 20px 0px 20px;
			margin-top: -22px;
		  }
		}`
		console.log(string)
		return string;
	}

  };

}).call(this);
