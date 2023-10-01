from docutils.parsers.rst import Directive
from docutils.statemachine import ViewList
from docutils import nodes
from docutils.parsers.rst.states import Inliner

class XeQuote(Directive):
    required_arguments = 1
    optional_arguments = 2
    has_content = True

    def run(self):
        persona = self.arguments[0] if self.arguments else None
        mood = self.arguments[1] if len(self.arguments) > 1 else None
        blockquote = nodes.block_quote()
        blockquote.set_class('xe-quote')
        image_node = nodes.image(uri=self.image_uri(persona, mood))
        nested_node = nodes.container()

        content = ViewList(self.content)
        self.state.nested_parse(content, 0, node=nested_node)

        blockquote += image_node
        blockquote += nested_node.children
        return [blockquote]

    def image_uri(self, persona, mood):
        if persona == 'shoebill':
            mapping = {
                'neutral': '/_static/breakelse/shoebill_neutral.png',
                'aghast': '/_static/breakelse/shoebill_aghast.png',
                'considering': '/_static/breakelse/shoebill_considering.png',
            }
            return mapping[mood or 'neutral']
        elif persona == 'gurkenglas':
            mapping = {
                'neutral': '/_static/breakelse/gurkenglas_neutral.png',
                'suggesting': '/_static/breakelse/gurkenglas_suggesting.png',
                'looking': '/_static/breakelse/gurkenglas_looking.png',
                'idea': '/_static/breakelse/gurkenglas_idea.png',
                'unimpressed': '/_static/breakelse/gurkenglas_unimpressed.png',
            }
            return mapping[mood or 'neutral']
        else:
            assert False


def setup(app):
    app.add_directive('xe-quote', XeQuote)

    return {
        'version': '0.1',
        'parallel_read_safe': True,
        'parallel_write_safe': True,
    }

